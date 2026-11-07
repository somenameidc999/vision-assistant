import AVFoundation
import OSLog
import Speech
import VisionCore

/// Network and audio analysis never execute on the audio tap callback.
final class VoiceSession: NSObject, AVSpeechSynthesizerDelegate {
    var onSpeechStart: (() -> Void)?
    var onInputLevel: ((Float) -> Void)?
    var onCaptionSamples: (([Float]) -> Void)?
    var onCaptionEnd: (() -> Void)?
    var onQuestion: ((Data, Date) -> Void)?
    var onSpeaking: ((Bool) -> Void)?
    var onFirstAudio: (() -> Void)?
    var onPlaybackCompleted: (() -> Void)?
    var onError: ((String) -> Void)?
    private let engine = AVAudioEngine()
    private let output = AVAudioPlayerNode()
    private let synthesizer = AVSpeechSynthesizer()
    private let work = DispatchQueue(label: "vision.voice.analysis")
    private var detector = VoiceDetector()
    private var analysisEnabled = false // Accessed only on work.
    private var converter: AVAudioConverter?
    private var epoch = UUID()
    private var speechEpoch = UUID()
    private var tapInstalled = false
    private var observers: [NSObjectProtocol] = []
    private var routeRecoveryTask: Task<Void, Never>?
    private var captureMonitor: Timer?
    private var lastInputAt = 0.0 // Accessed only on work.
    private var lastDiagnosticAt = 0.0 // Accessed only on work.
    private var lastLevelAt = 0.0 // Accessed only on work.
    private var lastRMS: Float = 0 // Accessed only on work.
    private var inputBufferCount = 0 // Accessed only on work.
    private var captionPrebuffer: [Float] = [] // Accessed only on work.
    private var running = false
    private var receivedFirstSpeechBuffer = false
    private var speechConverter: AVAudioConverter?
    private var currentUtterance: AVSpeechUtterance?
    private var pendingSpeechBuffers = 0
    private var synthesisFinished = false
    private let mono16 = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private let speechOutputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
    private let log = Logger(subsystem: "local.personal.VisionAssistant", category: "voice")
    override init() {
        super.init()
        engine.attach(output)
        synthesizer.delegate = self
        // Buffer generation must not manage the app's capture/render audio session.
        synthesizer.usesApplicationAudioSession = false
    }

    @MainActor
    func start() async throws {
        let microphoneAllowed: Bool
        if #available(iOS 17, *) {
            microphoneAllowed = await AVAudioApplication.requestRecordPermission()
        } else {
            microphoneAllowed = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
            }
        }
        guard microphoneAllowed else {
            throw DemoError(message: "Microphone permission is denied. Enable Microphone in Settings or use text questions.")
        }
        let audio = AVAudioSession.sharedInstance()
        log.info("Configuring voice audio session")
        try audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audio.setActive(true)
        // Apple requires the category, mode, and active session before requesting channels.
        try? audio.setPreferredInputNumberOfChannels(1)
        let channels = audio.inputNumberOfChannels
        log.info("Active audio route input channels: \(channels)")
        #if targetEnvironment(simulator)
        // The observed eight-channel Jump route aborts Core Audio inside AudioUnitInitialize.
        // That failure is not a Swift error, so detect the unsupported route before creating I/O.
        guard channels > 0, channels <= 2 else {
            throw DemoError(message: "Simulator’s current microphone has \(channels) channels and cannot initialize the voice engine safely. Select a mono or stereo microphone in Simulator > Device > Sound > Sound Input, then restart the session.")
        }
        #endif
        log.info("Enabling input voice processing")
        do { try engine.inputNode.setVoiceProcessingEnabled(true) }
        catch { throw DemoError(message: "Voice processing is unavailable on this audio route. Select another microphone route, or use text questions.") }
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let converter = AVAudioConverter(from: format, to: mono16) else {
            throw DemoError(message: "No microphone audio route is available. Check Simulator Sound Input and macOS microphone permission.")
        }
        self.converter = converter
        engine.connect(output, to: engine.mainMixerNode, format: speechOutputFormat)
        epoch = UUID(); let currentEpoch = epoch
        work.sync { detector.reset(); analysisEnabled = true; lastInputAt = CACurrentMediaTime(); lastDiagnosticAt = 0; lastLevelAt = 0; lastRMS = 0; inputBufferCount = 0; captionPrebuffer.removeAll() }
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // Own a copy before the callback returns; AVFoundation reuses its tap buffers.
            guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
            copy.frameLength = buffer.frameLength
            let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for index in 0..<min(source.count, destination.count) {
                if let input = source[index].mData, let output = destination[index].mData {
                    memcpy(output, input, Int(source[index].mDataByteSize))
                }
            }
            self?.work.async { [weak self] in self?.analyse(copy, converter: converter, epoch: currentEpoch) }
        }
        tapInstalled = true
        log.info("Starting audio engine")
        do { try engine.start(); running = true; log.info("Audio engine started") }
        catch { stop(); throw error }
        captureMonitor?.invalidate()
        captureMonitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.work.async { [weak self] in
                guard let self, self.analysisEnabled else { return }
                let age = CACurrentMediaTime() - self.lastInputAt
                let diagnostics: [String: Any] = ["at": Date().timeIntervalSince1970, "inputBufferAge": age,
                    "inputBufferCount": self.inputBufferCount, "rms": self.lastRMS,
                    "threshold": self.detector.detectionThreshold, "recording": self.detector.isRecording]
                Task { @MainActor [weak self] in
                    guard let self, self.running, self.epoch == currentEpoch else { return }
                    #if DEBUG
                    var snapshot = diagnostics
                    snapshot["engineRunning"] = self.engine.isRunning
                    snapshot["inputChannels"] = AVAudioSession.sharedInstance().inputNumberOfChannels
                    snapshot["inputSampleRate"] = self.engine.inputNode.outputFormat(forBus: 0).sampleRate
                    if let data = try? JSONSerialization.data(withJSONObject: snapshot),
                       let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                        try? data.write(to: directory.appendingPathComponent("voice-diagnostics.json"), options: .atomic)
                    }
                    #endif
                    if age > 2 {
                        self.log.notice("Voice diagnostics: input stalled; age \(age); engine running \(self.engine.isRunning)")
                        if !self.engine.isRunning {
                            do {
                                try AVAudioSession.sharedInstance().setActive(true)
                                try self.engine.start()
                                self.log.notice("Voice diagnostics: capture engine restarted")
                            } catch { self.onError?("The microphone could not restart.") }
                        }
                    }
                }
            }
        }
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification, AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: audio, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    guard let self, self.running, self.epoch == currentEpoch else { return }
                    if name == AVAudioSession.routeChangeNotification {
                        let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
                        self.scheduleRouteRecovery(reason: raw, epoch: currentEpoch)
                    } else if name == AVAudioSession.interruptionNotification {
                        let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                        guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
                        self.onError?("Audio was interrupted by another app or a call.")
                    } else {
                        self.onError?("The audio service restarted.")
                    }
                }
            })
        }
    }

    private func scheduleRouteRecovery(reason: UInt, epoch: UUID) {
        log.info("Audio route notification; reason: \(reason)")
        routeRecoveryTask?.cancel()
        routeRecoveryTask = Task { @MainActor [weak self] in
            // Startup, speaker routing, and synthesis can emit several routine notifications.
            // Wait for the route to settle before checking whether capture actually changed.
            do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            guard let self, self.running, self.epoch == epoch else { return }
            let format = self.engine.inputNode.outputFormat(forBus: 0)
            let expected = self.converter?.inputFormat
            guard !AVAudioSession.sharedInstance().currentRoute.inputs.isEmpty,
                  format.sampleRate > 0, format.channelCount > 0,
                  format.sampleRate == expected?.sampleRate,
                  format.channelCount == expected?.channelCount,
                  format.commonFormat == expected?.commonFormat else {
                self.log.info("Microphone format changed; explicit session resume required")
                self.onError?("The microphone changed or disconnected.")
                return
            }
            do {
                if !self.engine.isRunning {
                    try AVAudioSession.sharedInstance().setActive(true)
                    try self.engine.start()
                    if self.pendingSpeechBuffers > 0, !self.output.isPlaying { self.output.play() }
                }
                self.log.info("Audio route settled; capture continues; reason: \(reason)")
            } catch {
                self.onError?("Audio could not resume on this route.")
            }
        }
    }

    private func analyse(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, epoch: UUID) {
        // All invocations run on the single analysis queue.
        guard analysisEnabled else { return }
        let now = CACurrentMediaTime(); lastInputAt = now; inputBufferCount += 1
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / buffer.format.sampleRate) + 32)
        guard let converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return }
        var supplied = false, conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return buffer
        }
        guard conversionError == nil, let channel = converted.floatChannelData?[0] else { return }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
        let rms = Float(sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, samples.count))))
        lastRMS = rms
        if now - lastLevelAt >= 0.1 {
            lastLevelAt = now
            Task { @MainActor [weak self] in
                guard let self, self.running, self.epoch == epoch else { return }
                self.onInputLevel?(rms)
            }
        }
        let wasRecording = detector.isRecording
        if !wasRecording {
            captionPrebuffer.append(contentsOf: samples)
            if captionPrebuffer.count > 4800 { captionPrebuffer.removeFirst(captionPrebuffer.count - 4800) }
        }
        let events = detector.process(samples)
        if now - lastDiagnosticAt >= 1 {
            lastDiagnosticAt = now
            log.notice("Voice diagnostics: rms \(rms); threshold \(self.detector.detectionThreshold); recording \(self.detector.isRecording); frames \(converted.frameLength)")
        }
        let started = events.contains { if case .started = $0 { return true }; return false }
        let captionSamples = started ? captionPrebuffer : samples
        var question: Data?
        for event in events {
            if case .completed(let samples) = event { question = WAV.encode(samples) }
        }
        let endedAt = Date().addingTimeInterval(-0.7)
        if started { captionPrebuffer.removeAll(keepingCapacity: true); log.info("Microphone speech activity detected") }
        if wasRecording || started || question != nil {
            let completedQuestion = question
            DispatchQueue.main.async { [weak self] in
                guard let self, self.epoch == epoch, self.running else { return }
                if started { self.onSpeechStart?() }
                self.onCaptionSamples?(captionSamples)
                if let completedQuestion {
                    self.onCaptionEnd?()
                    self.onQuestion?(completedQuestion, endedAt)
                }
            }
        }
    }
    func setMuted(_ muted: Bool) {
        work.async { [weak self] in self?.analysisEnabled = !muted; self?.detector.reset(); self?.captionPrebuffer.removeAll() }
    }
    func speak(_ text: String) {
        stopSpeaking()
        guard running else { return }
        let speechEpoch = UUID(); self.speechEpoch = speechEpoch
        receivedFirstSpeechBuffer = false
        onSpeaking?(true)
        let utterance = AVSpeechUtterance(string: text)
        currentUtterance = utterance
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.write(utterance) { [weak self] buffer in
            guard let source = buffer as? AVAudioPCMBuffer else { return }
            // The buffer producer owns this storage. Copy before dispatching to the main queue.
            if source.frameLength <= 1 {
                self?.log.info("Speech terminal buffer received; frames: \(source.frameLength)")
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.running, self.speechEpoch == speechEpoch, self.receivedFirstSpeechBuffer else { return }
                    self.synthesisFinished = true
                    self.finishSpeechIfDrained()
                }
                return
            }
            guard let pcm = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return }
            pcm.frameLength = source.frameLength
            let sourceBuffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
            let destinationBuffers = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
            for index in 0..<min(sourceBuffers.count, destinationBuffers.count) {
                if let input = sourceBuffers[index].mData, let output = destinationBuffers[index].mData {
                    memcpy(output, input, Int(sourceBuffers[index].mDataByteSize))
                }
            }
            DispatchQueue.main.async {
                guard let self, self.running, self.speechEpoch == speechEpoch else { return }
                guard pcm.frameLength > 0 else { return }
                if self.speechConverter == nil {
                    self.speechConverter = AVAudioConverter(from: pcm.format, to: self.speechOutputFormat)
                }
                guard let converter = self.speechConverter else {
                    self.onError?("The speech audio format could not be converted. End the session and try again.")
                    return
                }
                let capacity = AVAudioFrameCount(ceil(Double(pcm.frameLength) * self.speechOutputFormat.sampleRate / pcm.format.sampleRate) + 32)
                guard let converted = AVAudioPCMBuffer(pcmFormat: self.speechOutputFormat, frameCapacity: capacity) else { return }
                var supplied = false, conversionError: NSError?
                converter.convert(to: converted, error: &conversionError) { _, status in
                    if supplied { status.pointee = .noDataNow; return nil }
                    supplied = true; status.pointee = .haveData; return pcm
                }
                guard conversionError == nil else {
                    self.onError?("Speech audio conversion failed. End the session and try again.")
                    return
                }
                guard converted.frameLength > 0 else { return }
                guard self.resumeSpeechRenderingIfNeeded() else { return }
                if !self.receivedFirstSpeechBuffer {
                    self.receivedFirstSpeechBuffer = true
                    self.log.info("First speech audio buffer scheduled")
                    self.onFirstAudio?()
                }
                self.pendingSpeechBuffers += 1
                self.output.scheduleBuffer(converted, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self, self.speechEpoch == speechEpoch else { return }
                        self.pendingSpeechBuffers -= 1
                        self.finishSpeechIfDrained()
                    }
                }
                if !self.output.isPlaying { self.output.play() }
            }
        }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.currentUtterance === utterance else { return }
            self.synthesisFinished = true
            self.log.info("Speech synthesis finished; pending buffers: \(self.pendingSpeechBuffers), engine running: \(self.engine.isRunning)")
            if self.pendingSpeechBuffers > 0, self.resumeSpeechRenderingIfNeeded(), !self.output.isPlaying { self.output.play() }
            self.finishSpeechIfDrained()
        }
    }
    private func resumeSpeechRenderingIfNeeded() -> Bool {
        guard running else { return false }
        do {
            if !engine.isRunning {
                try AVAudioSession.sharedInstance().setActive(true)
                try engine.start()
                log.info("Audio rendering resumed after speech session reconfiguration")
            }
            return true
        } catch {
            onError?("Speech playback could not restart the audio engine. End the session and try again.")
            return false
        }
    }
    private func finishSpeechIfDrained() {
        guard running, synthesisFinished, pendingSpeechBuffers == 0 else { return }
        guard receivedFirstSpeechBuffer else {
            onError?("The speech synthesizer returned no playable audio. End the session and try again.")
            return
        }
        currentUtterance = nil; speechEpoch = UUID()
        log.info("Speech playback completed")
        onPlaybackCompleted?(); onSpeaking?(false)
    }
    func stopSpeaking() {
        speechEpoch = UUID()
        currentUtterance = nil; pendingSpeechBuffers = 0; synthesisFinished = false
        synthesizer.stopSpeaking(at: .immediate)
        output.stop(); speechConverter = nil; onSpeaking?(false)
    }
    func stop() {
        epoch = UUID(); running = false; captureMonitor?.invalidate(); captureMonitor = nil; routeRecoveryTask?.cancel(); routeRecoveryTask = nil; stopSpeaking()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine.stop()
        work.sync { analysisEnabled = false; detector.reset() }
        converter = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}


/// Partial recognition stays on the iPhone. Never fall back to Apple's servers.
@MainActor
final class LiveCaptions {
    var onText: ((String) -> Void)?
    var onUnavailable: ((String) -> Void)?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var epoch = UUID()
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private var enabled = false
    private var ending = false
    private let log = Logger(subsystem: "local.personal.VisionAssistant", category: "captions")

    func prepare() async {
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        log.notice("Caption diagnostics: authorization \(authorization.rawValue)")
        guard authorization == .authorized else {
            enabled = false
            onUnavailable?("Allow Speech Recognition in Settings for live words. Spoken questions still work.")
            return
        }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            enabled = false
            onUnavailable?("On-device live words are unavailable. Spoken questions still work.")
            return
        }
        self.recognizer = recognizer; enabled = true
        log.notice("Caption diagnostics: on-device recognition supported")
    }
    func begin() {
        cancel()
        guard enabled, let recognizer else { return }
        ending = false
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        self.request = request
        let epoch = epoch
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.epoch == epoch else { return }
                if let result {
                    self.log.notice("Caption diagnostics: characters \(result.bestTranscription.formattedString.count); final \(result.isFinal)")
                    self.onText?(result.bestTranscription.formattedString)
                }
                if result?.isFinal == true { self.task = nil; self.request = nil }
                else if error != nil {
                    self.task = nil; self.request = nil
                    let code = (error as NSError?)?.code ?? 0
                    self.log.notice("Caption diagnostics: on-device recognition failed; code \(code)")
                    if !self.ending {
                        self.onUnavailable?("Live words are temporarily unavailable. Spoken questions still work.")
                    }
                }
            }
        }
    }
    func append(_ samples: [Float]) {
        guard let request, !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: source.count) }
        }
        request.append(buffer)
    }
    func finish() { ending = true; request?.endAudio() }
    func cancel() {
        epoch = UUID(); request?.endAudio(); task?.cancel(); task = nil; request = nil
    }
}
