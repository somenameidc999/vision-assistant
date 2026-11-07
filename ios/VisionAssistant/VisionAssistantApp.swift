import SwiftUI
import AVFoundation

@main
struct VisionAssistantApp: App {
    var body: some Scene { WindowGroup { AssistantView() } }
}

struct AssistantView: View {
    @StateObject private var model = AssistantModel()
    @Environment(\.scenePhase) private var phase
    @State private var showConfiguration = false
    @FocusState private var questionFocused: Bool
    var body: some View {
        NavigationStack {
            Group {
                if !model.active {
                    GeometryReader { geometry in
                        ZStack {
                            Button(action: model.start) {
                                ZStack {
                                    Circle().fill(Color.accentColor)
                                    if model.starting { ProgressView().tint(.white) }
                                    else { Image(systemName: "camera.fill").font(.system(size: 34, weight: .medium)).foregroundStyle(.white) }
                                }.frame(width: 104, height: 104)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Start session")
                            .accessibilityIdentifier("startSession")
                            .disabled(model.starting)
                            .contextMenu {
                                Button { showConfiguration = true } label: { Label("Connection", systemImage: "network") }
                            }
                            if let message = model.message {
                                VStack { Spacer(); Text(message).font(.callout).foregroundStyle(.orange)
                                    .multilineTextAlignment(.center).padding().accessibilityIdentifier("statusMessage") }
                            }
                        }.frame(width: geometry.size.width, height: geometry.size.height)
                    }
                } else {
                    conversation
                }
            }
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--start-session") { model.start() }
                #endif
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showConfiguration) {
                NavigationStack {
                    Form {
                        TextField("Backend URL", text: $model.configuration.backendURL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Session token", text: $model.configuration.sessionToken)
                        Text("Simulator uses localhost. An iPhone uses your Mac’s Tailscale URL or local network address. Long-press the start button to open these settings. This token is for the local backend, not your OpenRouter credential.")
                    }.navigationTitle("Connection").toolbar { Button("Done") { showConfiguration = false } }
                }
            }
            .onChange(of: phase) { newPhase in
                if newPhase == .background && (model.active || model.starting) { model.pause(reason: "The app left the foreground.") }
            }
        }
    }
    private var conversation: some View {
        ZStack {
            Group {
                #if DEBUG && targetEnvironment(simulator)
                if model.developmentScene { MoviePreview(player: model.video.player) }
                else { CameraPreview(session: model.camera.session, facing: model.cameraFacing) }
                #else
                CameraPreview(session: model.camera.session, facing: model.cameraFacing)
                #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black).ignoresSafeArea()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.developmentScene ? "Development scene" : "Live camera")
            .accessibilityIdentifier("scenePreview")

            LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 14) {
                HStack {
                    Text(model.developmentScene ? "DEVELOPMENT VIDEO" : model.cameraFacing.title.uppercased())
                        .font(.caption2.bold()).padding(10).background(.black.opacity(0.45), in: Capsule())
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Circle().fill(model.muted ? .gray : .green)
                            .frame(width: 8 + CGFloat(model.microphoneLevel) * 8, height: 8 + CGFloat(model.microphoneLevel) * 8)
                            .frame(width: 20, height: 20).accessibilityLabel("Microphone level")
                        Text(model.status).font(.subheadline.weight(.medium)).lineLimit(1)
                            .accessibilityIdentifier("assistantState")
                            .accessibilityValue(model.speechPlaybackCompleted ? "Speech playback completed" : "")
                    }.padding(8).background(.black.opacity(0.45), in: Capsule())
                }
                Spacer(minLength: 12)
                if let message = model.message {
                    Text(message).font(.callout).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("statusMessage")
                }
                if !model.lines.isEmpty || !model.liveTranscript.isEmpty {
                    ScrollViewReader { scroll in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(model.lines) { line in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(line.isAssistant ? "Assistant" : "You").font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
                                        Text(line.text).textSelection(.enabled).accessibilityIdentifier(line.isAssistant ? "assistantReply" : "userQuestion")
                                        if line.interrupted { Text("Interrupted").font(.caption).foregroundStyle(.orange) }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(.black.opacity(line.isAssistant ? 0.7 : 0.5), in: RoundedRectangle(cornerRadius: 16))
                                    .id(line.id)
                                }
                                if !model.liveTranscript.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("You").font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
                                        Text(model.liveTranscript).accessibilityIdentifier("liveTranscript")
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16)).id("liveDraft")
                                }
                            }
                        }
                        .frame(maxHeight: questionFocused ? 120 : 190)
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: model.lines.count) { _ in
                            if let last = model.lines.last { withAnimation(.easeOut(duration: 0.2)) { scroll.scrollTo(last.id, anchor: .bottom) } }
                        }
                        .onChange(of: model.liveTranscript) { text in
                            if !text.isEmpty { scroll.scrollTo("liveDraft", anchor: .bottom) }
                        }
                    }
                }
                VStack(spacing: 12) {
                    if let notice = model.captionNotice {
                        Text(notice).font(.caption).foregroundStyle(.white.opacity(0.8)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        TextField("Ask about the scene", text: $model.question, axis: .vertical)
                            .lineLimit(1...3).padding(10).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityIdentifier("questionInput").focused($questionFocused)
                        Button {
                            questionFocused = false; model.sendText()
                        } label: { Label("Send", systemImage: "arrow.up.circle.fill") }
                            .labelStyle(.iconOnly).font(.title).accessibilityIdentifier("sendQuestion")
                    }.disabled(model.starting || model.switchingCamera || model.frameCount == 0)
                    HStack {
                        control(model.muted ? "Unmute" : "Mute", icon: model.muted ? "mic.slash.fill" : "mic.fill", id: "muteMicrophone", action: model.toggleMute)
                            .disabled(model.starting)
                        Spacer()
                        control("Stop speaking", icon: "speaker.slash.fill", id: "stopSpeaking", action: model.interrupt)
                            .disabled(model.starting || model.status != "Speaking")
                            .opacity(model.status == "Speaking" ? 1 : 0.45)
                        Spacer()
                        control("Switch to \(model.cameraFacing.opposite.title.lowercased())", icon: "arrow.triangle.2.circlepath.camera", id: "switchCamera", action: model.switchCamera)
                            .disabled(model.starting || model.switchingCamera || model.developmentScene)
                        Spacer()
                        control("End session", icon: "stop.fill", id: "endSession", destructive: true, action: model.end)
                    }
                }.padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }.foregroundStyle(.white).preferredColorScheme(.dark)
    }

    private func control(_ label: String, icon: String, id: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3).frame(width: 52, height: 48)
                .background(destructive ? Color.red.opacity(0.85) : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain).foregroundStyle(.white)
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

}

#if DEBUG && targetEnvironment(simulator)
private final class MovieSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
private struct MoviePreview: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> MovieSurface { let view = MovieSurface(); view.playerLayer.videoGravity = .resizeAspectFill; return view }
    func updateUIView(_ view: MovieSurface, context: Context) { view.playerLayer.player = player }
}
#endif
private final class CameraSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private var rotation: AnyObject?
    private var rotationObservation: NSKeyValueObservation?
    func refreshRotation() {
        guard let device = (previewLayer.session?.inputs.first as? AVCaptureDeviceInput)?.device,
              let connection = previewLayer.connection else { return }
        if #available(iOS 17, *) {
            var coordinator = rotation as? AVCaptureDevice.RotationCoordinator
            if coordinator?.device !== device {
                rotationObservation = nil
                coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
                rotation = coordinator
                let deviceId = device.uniqueID
                rotationObservation = coordinator?.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, change in
                    guard let angle = change.newValue else { return }
                    Task { @MainActor in
                        guard let self,
                              (self.rotation as? AVCaptureDevice.RotationCoordinator)?.device?.uniqueID == deviceId else { return }
                        self.applyRotation(angle)
                    }
                }
            }
            if let angle = coordinator?.videoRotationAngleForHorizonLevelPreview { applyRotation(angle) }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }
    @available(iOS 17, *)
    private func applyRotation(_ angle: CGFloat) {
        guard let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
    override func layoutSubviews() { super.layoutSubviews(); refreshRotation() }
}
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let facing: CameraFacing
    func makeUIView(context: Context) -> CameraSurface { let view = CameraSurface(); view.previewLayer.videoGravity = .resizeAspectFill; return view }
    func updateUIView(_ view: CameraSurface, context: Context) {
        view.previewLayer.session = session
        view.refreshRotation()
    }
}
