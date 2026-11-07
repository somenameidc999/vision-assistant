import AVFoundation
import UIKit
import VisionCore

@MainActor
protocol FrameSource: AnyObject {
    var onFrame: ((SceneFrame) -> Void)? { get set }
    var onReset: (() -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    func start() async throws
    func requestFrame()
    func stop()
}

private func jpeg(_ image: UIImage) -> Data? {
    let scale = min(1, 1024 / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
    }.jpegData(compressionQuality: 0.7)
}

#if DEBUG && targetEnvironment(simulator)
@MainActor
final class PrerecordedSource: FrameSource {
    var onFrame: ((SceneFrame) -> Void)?
    var onReset: (() -> Void)?
    var onError: ((String) -> Void)?
    let player = AVPlayer()
    private var output: AVPlayerItemVideoOutput?
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var sourceId = UUID()
    private let context = CIContext()
    func start() async throws {
        guard let url = Bundle.main.url(forResource: "demo-scene", withExtension: "mp4") else {
            throw DemoError(message: "The demo video is missing. Run scripts/make_fixtures.py before generating the Xcode project.")
        }
        stop(); sourceId = UUID(); onReset?()
        let item = AVPlayerItem(url: url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output); self.output = output
        player.replaceCurrentItem(with: item); player.isMuted = true
        observer = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.timer != nil else { return }
                self.sourceId = UUID(); self.onReset?()
                await self.player.seek(to: .zero)
                guard self.timer != nil else { return }
                self.player.play()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        player.play()
    }
    func requestFrame() { sample() }
    private func sample() {
        guard let output, player.rate > 0 else { return }
        let time = player.currentTime()
        guard let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cg = context.createCGImage(image, from: image.extent), let data = jpeg(UIImage(cgImage: cg)) else { return }
        onFrame?(SceneFrame(sourceId: sourceId, playbackSeconds: time.seconds, jpeg: data))
    }
    func stop() {
        timer?.invalidate(); timer = nil
        player.pause(); player.replaceCurrentItem(with: nil); output = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil
    }
}

#endif

enum CameraFacing {
    case rear, front
    var position: AVCaptureDevice.Position { self == .rear ? .back : .front }
    var title: String { self == .rear ? "Rear camera" : "Front camera" }
    var opposite: CameraFacing { self == .rear ? .front : .rear }
}

/// All session mutations and image delivery run on the same serial queue.
// Mutable capture state belongs to queue. The callback is installed before that queue starts.
private final class CameraPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "vision.camera")
    var onFrame: ((Data, Date, UUID) -> Void)?
    private var sourceId = UUID()
    private var lastSample: Double = 0
    private var captureStartedAt = CMTime.invalid
    private let context = CIContext()
    private var rotation: AnyObject?
    private var rotationObservation: NSKeyValueObservation?

    func configure(facing: CameraFacing, sourceId: UUID, start: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: facing.position) else {
                        throw DemoError(message: "No \(facing.title.lowercased()) is available. Use an iPhone for a live camera session.")
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    let previous = self.session.inputs.first
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .hd1280x720
                    if let previous { self.session.removeInput(previous) }
                    guard self.session.canAddInput(input) else {
                        if let previous, self.session.canAddInput(previous) { self.session.addInput(previous) }
                        self.session.commitConfiguration()
                        throw DemoError(message: "Cannot switch cameras. The previous camera remains selected.")
                    }
                    self.session.addInput(input)
                    if self.session.outputs.isEmpty {
                        let output = AVCaptureVideoDataOutput()
                        output.alwaysDiscardsLateVideoFrames = true
                        output.setSampleBufferDelegate(self, queue: self.queue)
                        guard self.session.canAddOutput(output) else {
                            self.session.commitConfiguration()
                            throw DemoError(message: "Camera configuration failed.")
                        }
                        self.session.addOutput(output)
                    }
                    self.session.commitConfiguration()
                    self.sourceId = sourceId; self.lastSample = 0
                    self.captureStartedAt = self.session.synchronizationClock.map { CMClockGetTime($0) } ?? .invalid
                    self.rotationObservation = nil
                    if #available(iOS 17, *) {
                        let rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
                        self.rotation = rotation
                        self.rotateOutput(rotation.videoRotationAngleForHorizonLevelCapture)
                        self.rotationObservation = rotation.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, change in
                            guard let angle = change.newValue else { return }
                            self?.queue.async { [weak self] in
                                guard let self, self.sourceId == sourceId else { return }
                                self.rotateOutput(angle)
                            }
                        }
                    } else if let connection = self.session.outputs.first?.connection(with: .video) {
                        // The app supports portrait only. AVFoundation handles front/rear sensor orientation.
                        if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
                        if connection.isVideoMirroringSupported {
                            connection.automaticallyAdjustsVideoMirroring = false
                            connection.isVideoMirrored = false
                        }
                    }
                    if start { self.session.startRunning() }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    @available(iOS 17, *)
    private func rotateOutput(_ angle: CGFloat) {
        guard let connection = session.outputs.first?.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }
    func requestFrame() { queue.async { self.lastSample = 0 } }
    func stop() { queue.async { self.session.stopRunning(); self.rotationObservation = nil } }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let presentation = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        // Reject buffers captured before the input change, even if their delegate call was queued later.
        guard presentation.isValid, !captureStartedAt.isValid || CMTimeCompare(presentation, captureStartedAt) >= 0 else { return }
        let now = CACurrentMediaTime()
        guard now - lastSample >= 1, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastSample = now
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cg = context.createCGImage(image, from: image.extent), let data = jpeg(UIImage(cgImage: cg)) else { return }
        let age = session.synchronizationClock.map { CMTimeGetSeconds(CMTimeSubtract(CMClockGetTime($0), presentation)) } ?? 0
        guard age.isFinite else { return }
        onFrame?(data, Date().addingTimeInterval(-max(0, age)), sourceId)
    }
}

@MainActor
final class CameraSource: FrameSource {
    var onFrame: ((SceneFrame) -> Void)?
    var onReset: (() -> Void)?
    var onError: ((String) -> Void)?
    private var pipeline = CameraPipeline()
    var session: AVCaptureSession { pipeline.session }
    private(set) var facing: CameraFacing = .rear
    private var sourceId = UUID()
    private var running = false
    private var generation = UUID()
    private var observers: [NSObjectProtocol] = []
    func start() async throws {
        let generation = generation, pipeline = pipeline
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        guard self.generation == generation, self.pipeline === pipeline else { throw CancellationError() }
        guard allowed else { throw DemoError(message: "Camera permission is denied. Enable Camera in Settings, then resume.") }
        sourceId = UUID(); onReset?(); running = true
        pipeline.onFrame = { [weak self] data, date, sourceId in Task { @MainActor in
            guard let self, self.running, self.sourceId == sourceId else { return }
            self.onFrame?(SceneFrame(capturedAt: date, sourceId: sourceId, jpeg: data))
        } }
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: pipeline.session, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.running, self.pipeline === pipeline else { return }
                    self.onError?("Camera capture was interrupted. End the session, then resume.")
                }
            })
        }
        do {
            try await pipeline.configure(facing: facing, sourceId: sourceId, start: true)
            guard self.generation == generation, self.pipeline === pipeline else { throw CancellationError() }
        } catch {
            if self.pipeline === pipeline { stop() }
            throw error
        }
    }
    func requestFrame() { pipeline.requestFrame() }
    func switchCamera() async throws {
        guard running else { return }
        let pipeline = pipeline, next = facing.opposite, nextId = UUID()
        try await pipeline.configure(facing: next, sourceId: nextId, start: false)
        guard running, self.pipeline === pipeline else { return }
        sourceId = nextId; facing = next; onReset?()
    }
    func stop() {
        generation = UUID(); running = false; pipeline.stop()
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        pipeline = CameraPipeline()
    }
}
