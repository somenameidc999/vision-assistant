import SwiftUI
import AVFoundation
import VisionCore

struct ConversationLine: Identifiable {
    let id = UUID()
    let turnId: UUID
    let isAssistant: Bool
    let text: String
    var interrupted = false
}

@MainActor
final class AssistantModel: ObservableObject {
    @Published var configuration = LocalConfiguration.load()
    @Published var lines: [ConversationLine] = []
    @Published var status = "Ready"
    @Published var message: String?
    @Published var active = false
    @Published var starting = false
    @Published var muted = false
    @Published var frameCount = 0
    @Published var question = ""
    @Published var metrics = ""
    @Published private(set) var cameraFacing = CameraFacing.rear
    @Published private(set) var switchingCamera = false
    #if DEBUG && targetEnvironment(simulator)
    let developmentScene = ProcessInfo.processInfo.arguments.contains("--dev-prerecorded-scene")
    let video = PrerecordedSource()
    #else
    let developmentScene = false
    #endif
    @Published var speechPlaybackCompleted = false
    @Published var microphoneLevel: Float = 0
    @Published var liveTranscript = ""
    @Published var captionNotice: String?
    let camera = CameraSource()
    private var source: any FrameSource {
        #if DEBUG && targetEnvironment(simulator)
        if developmentScene { return video }
        #endif
        return camera
    }
    private let voice = VoiceSession()
    private let captions = LiveCaptions()
    private var history = SceneHistory()
    private var client: BackendClient?
    private var sessionId: UUID?
    private var turnId: UUID?
    private var requestTask: Task<Void, Never>?
    private var cancellationTask: Task<Void, Never>?
    private var generation = UUID()
    private var voiceAvailable = false
    private var speechEndedAt: Date?
    private var speaking = false
    private var observationGeneration = UUID()
    private var idleStatus: String { voiceAvailable ? (muted ? "Microphone muted" : "Listening") : "Text mode" }

    init() {
        var sources: [any FrameSource] = [camera]
        #if DEBUG && targetEnvironment(simulator)
        sources.append(video)
        #endif
        for source in sources {
            source.onFrame = { [weak self] frame in
                guard let self, !self.switchingCamera, self.active || self.starting else { return }
                self.history.append(frame); self.frameCount = self.history.frames.count
            }
            source.onReset = { [weak self] in
                guard let self else { return }
                self.observationGeneration = UUID(); self.history.clear(); self.frameCount = 0
                self.interrupt()
            }
            source.onError = { [weak self] error in self?.pause(reason: error) }
        }
        captions.onText = { [weak self] text in
            guard let self, self.active, !self.muted, !self.switchingCamera else { return }
            self.liveTranscript = text; self.captionNotice = nil
        }
        captions.onUnavailable = { [weak self] message in self?.captionNotice = message }
        voice.onCaptionSamples = { [weak self] samples in
            guard let self, self.active, !self.muted, !self.switchingCamera else { return }
            self.captions.append(samples)
        }
        voice.onCaptionEnd = { [weak self] in self?.captions.finish() }
        voice.onInputLevel = { [weak self] level in
            guard let self, self.active, !self.muted else { return }
            self.microphoneLevel = min(1, level * 15)
        }
        voice.onSpeechStart = { [weak self] in
            guard let self, self.active, !self.muted, !self.switchingCamera else { return }
            self.interrupt(); self.liveTranscript = ""; self.captions.begin(); self.status = "Hearing you"
        }
        voice.onQuestion = { [weak self] data, ended in
            guard let self, self.active, !self.muted, !self.switchingCamera else { return }
            self.submit(text: nil, audio: data, speechEndedAt: ended)
        }
        voice.onSpeaking = { [weak self] speaking in
            guard let self, self.active else { return }
            let previouslySpeaking = self.speaking
            self.speaking = speaking
            if previouslySpeaking && !speaking { self.turnId = nil }
            self.status = speaking ? "Speaking" : (self.requestTask == nil ? self.idleStatus : "Thinking")
        }
        voice.onPlaybackCompleted = { [weak self] in
            guard let self, self.active else { return }
            self.speechPlaybackCompleted = true
        }
        voice.onFirstAudio = { [weak self] in
            guard let self, self.active, let ended = self.speechEndedAt else { return }
            let delay = Date().timeIntervalSince(ended)
            self.metrics += String(format: " · speech end → playback scheduled %.1fs", delay)
            // Scheduling is an approximation. Actual audible delay requires loopback measurement.
            self.speechEndedAt = nil
        }
        voice.onError = { [weak self] error in self?.pause(reason: error) }
    }

    func start() {
        guard !active, !starting else { return }
        starting = true; message = nil; status = "Starting"
        let generation = UUID(); self.generation = generation
        let client = BackendClient(config: configuration); self.client = client
        Task {
            var createdSession: UUID?
            do {
                let id = try await client.start(); createdSession = id
                guard self.generation == generation else { await client.end(sessionId: id); return }
                self.sessionId = id
                try await self.source.start()
                guard self.generation == generation else { await client.end(sessionId: id); return }
                self.active = true
                self.captionNotice = nil
                await self.captions.prepare()
                guard self.generation == generation, self.active else { self.captions.cancel(); return }
                do { try await self.voice.start(); self.voiceAvailable = true }
                catch {
                    self.voice.stop(); self.voiceAvailable = false
                    self.message = error.localizedDescription + " Text questions remain available."
                }
                guard self.generation == generation, self.active else { self.voice.stop(); return }
                self.starting = false; self.muted = !self.voiceAvailable
                self.status = self.voiceAvailable ? "Listening" : "Text mode"
            } catch {
                if let createdSession { await client.end(sessionId: createdSession) }
                guard self.generation == generation else { return }
                self.source.stop(); self.voice.stop(); self.sessionId = nil
                self.active = false; self.starting = false; self.status = "Error"; self.message = error.localizedDescription
            }
        }
    }
    func sendText() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        question = ""; submit(text: text, audio: nil, speechEndedAt: nil)
    }
    private func submit(text: String?, audio: Data?, speechEndedAt: Date?) {
        guard active, !switchingCamera, let client, let sessionId else { return }
        interrupt()
        let turn = UUID(); turnId = turn
        let generation = generation, sceneGeneration = observationGeneration
        self.speechEndedAt = speechEndedAt; status = "Thinking"; message = nil; speechPlaybackCompleted = false
        if let text { lines.append(ConversationLine(turnId: turn, isAssistant: false, text: text)) }
        let cancellation = cancellationTask
        requestTask = Task {
            await cancellation?.value
            guard !Task.isCancelled, self.generation == generation, self.turnId == turn else { return }
            do {
                let reply = try await self.performTurn(client: client, sessionId: sessionId, turnId: turn, text: text, audio: audio)
                guard !Task.isCancelled, self.active, self.generation == generation,
                      self.observationGeneration == sceneGeneration, self.turnId == reply.turnId else { return }
                self.captions.cancel(); self.liveTranscript = ""
                if text == nil { self.lines.append(ConversationLine(turnId: turn, isAssistant: false, text: reply.transcript)) }
                self.lines.append(ConversationLine(turnId: turn, isAssistant: true, text: reply.answer))
                if self.lines.count > 32 { self.lines.removeFirst(self.lines.count - 32) }
                self.metrics = String(format: "Model %.1fs · accounted $%.3f / $%.0f", Double(reply.timing.providerMs) / 1000,
                    reply.budget.accountedUSD, reply.budget.limitUSD)
                self.requestTask = nil
                self.status = self.idleStatus
                if self.voiceAvailable { self.voice.speak(reply.answer) }
            } catch {
                guard !Task.isCancelled, self.active, self.generation == generation, self.turnId == turn else { return }
                self.requestTask = nil; self.status = "Error"; self.message = error.localizedDescription
            }
        }
    }
    private func freshFrames() async throws -> [SceneFrame] {
        let requestedAt = Date()
        source.requestFrame()
        for _ in 0..<30 {
            try Task.checkCancellation()
            let frames = history.selected()
            if let latest = frames.last, latest.capturedAt >= requestedAt.addingTimeInterval(-0.1) { return frames }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw DemoError(message: "The camera isn't updating. Switch cameras or end the session and try again.")
    }
    private func performTurn(client: BackendClient, sessionId: UUID, turnId: UUID, text: String?, audio: Data?) async throws -> TurnReply {
        for attempt in 0..<2 {
            let frames = try await freshFrames()
            try Task.checkCancellation()
            do { return try await client.turn(sessionId: sessionId, turnId: turnId, text: text, audio: audio, frames: frames) }
            catch let error as DemoError where error.code == "stale_frame" && attempt == 0 {
                // The backend rejects stale frames before reserving budget or calling a model.
                // Refresh once; never replay a request that may already have reached the model.
                continue
            }
        }
        throw DemoError(message: "A fresh view could not reach the backend. Check the connection and try again.")
    }
    func interrupt() {
        let interruptedTurn = turnId
        let needsCancel = requestTask != nil || speaking
        voice.stopSpeaking(); requestTask?.cancel(); requestTask = nil
        if needsCancel, let turnId = interruptedTurn, let client, let sessionId {
            let previous = cancellationTask
            cancellationTask = Task { await previous?.value; await client.cancel(sessionId: sessionId, turnId: turnId) }
            if let index = lines.lastIndex(where: { $0.turnId == turnId && $0.isAssistant }) { lines[index].interrupted = true }
        }
        turnId = nil; speechEndedAt = nil
    }
    func toggleMute() {
        guard voiceAvailable else { message = "End the session and resume after fixing microphone access."; return }
        muted.toggle(); voice.setMuted(muted)
        if muted { captions.cancel(); liveTranscript = ""; microphoneLevel = 0 }
        status = muted ? "Microphone muted" : "Listening"
    }
    func switchCamera() {
        guard active, !starting, !switchingCamera, !developmentScene else { return }
        interrupt(); captions.cancel(); liveTranscript = ""; voice.setMuted(muted)
        observationGeneration = UUID(); history.clear(); frameCount = 0
        switchingCamera = true; status = "Switching camera"; message = nil
        let generation = generation
        Task {
            do {
                try await camera.switchCamera()
                guard self.active, self.generation == generation else { return }
                self.cameraFacing = self.camera.facing
            } catch {
                guard self.active, self.generation == generation else { return }
                self.message = error.localizedDescription
            }
            guard self.active, self.generation == generation else { return }
            self.switchingCamera = false; self.status = self.idleStatus
        }
    }
    func end() {
        generation = UUID(); interrupt()
        #if DEBUG && targetEnvironment(simulator)
        video.stop()
        #endif
        camera.stop(); voice.stop(); captions.cancel(); liveTranscript = ""; captionNotice = nil; switchingCamera = false
        active = false; starting = false; voiceAvailable = false; microphoneLevel = 0
        history.clear(); frameCount = 0; status = "Ready"
        // Conversation content is session-only. Ending clears local content immediately.
        lines.removeAll(); metrics = ""; speechPlaybackCompleted = false
        if let sessionId, let client { Task { await client.end(sessionId: sessionId) } }
        sessionId = nil
    }
    func pause(reason: String) { end(); status = "Paused"; message = reason + " Tap the camera button to resume." }
}
