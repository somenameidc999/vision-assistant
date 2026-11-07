import XCTest
@testable import VisionCore

final class CoreTests: XCTestCase {
    @MainActor
    func testRecoverySurvivesRelaunchAndLateCleanupPreservesNewSession() {
        let suite = "VisionAssistant-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let endpoint = "http://localhost:18787", old = UUID(), new = UUID()
        let first = SessionRecoveryStore(defaults: defaults)
        first.record(old, for: endpoint)
        let relaunched = SessionRecoveryStore(defaults: defaults)
        XCTAssertEqual(relaunched.previous(for: endpoint), old)
        XCTAssertNil(relaunched.previous(for: "http://another-mac.local:18787"))
        relaunched.record(new, for: endpoint)
        relaunched.clear(old, for: endpoint)
        XCTAssertEqual(relaunched.previous(for: endpoint), new)
        relaunched.clear(new, for: endpoint)
        XCTAssertNil(relaunched.previous(for: endpoint))
    }
    func testPrivateBackendAddressBoundaries() {
        for host in ["192.168.42.10", "10.0.0.1", "172.16.0.1", "172.31.255.254"] {
            XCTAssertTrue(BackendAddress.isPrivateIPv4(host), host)
        }
        for host in ["8.8.8.8", "127.0.0.1", "169.254.1.2", "172.15.0.1", "172.32.0.1", "192.169.1.1", "10.01.2.3", "10.256.2.3", "10..2.3", "10.1.2.3.evil.test"] {
            XCTAssertFalse(BackendAddress.isPrivateIPv4(host), host)
        }
    }
    func testTimestampsPreserveMillisecondsAndAlignDeviceClock() {
        let date = Date(timeIntervalSince1970: 1000.875)
        XCTAssertEqual(SceneTimestamp.decode(SceneTimestamp.encode(date))!.timeIntervalSince1970, 1000.875, accuracy: 0.001)
        let offset = SceneTimestamp.clockOffset(serverTime: SceneTimestamp.encode(Date(timeIntervalSince1970: 1010.1)),
            sentAt: Date(timeIntervalSince1970: 1000), receivedAt: Date(timeIntervalSince1970: 1000.2))
        XCTAssertEqual(offset!, 10, accuracy: 0.001)
        XCTAssertNil(SceneTimestamp.clockOffset(serverTime: "invalid", sentAt: date, receivedAt: date))
        XCTAssertNil(SceneTimestamp.clockOffset(serverTime: SceneTimestamp.encode(date), sentAt: date, receivedAt: date.addingTimeInterval(6)))
    }
    func testWindowAndSelectionAlwaysIncludeNewest() {
        let now = Date(), source = UUID()
        var history = SceneHistory()
        for i in 0...40 {
            history.append(SceneFrame(capturedAt: now.addingTimeInterval(Double(i - 40)), sourceId: source, jpeg: Data([1])))
        }
        let selected = history.selected(now: now)
        XCTAssertEqual(history.frames.count, 31)
        XCTAssertEqual(selected.count, 6)
        XCTAssertEqual(selected.first?.capturedAt, now.addingTimeInterval(-30))
        XCTAssertEqual(selected.last?.capturedAt, now)
        XCTAssertEqual(Set(selected.map(\.id)).count, 6)
        XCTAssertTrue(history.selected(now: now.addingTimeInterval(3)).isEmpty)
    }
    func testSourceChangeAndPlaybackRewindClearHistory() {
        var history = SceneHistory(); let now = Date(), source = UUID()
        history.append(SceneFrame(capturedAt: now, sourceId: source, playbackSeconds: 12, jpeg: Data()))
        history.append(SceneFrame(capturedAt: now.addingTimeInterval(1), sourceId: source, playbackSeconds: 1, jpeg: Data()))
        XCTAssertEqual(history.frames.count, 1)
        history.append(SceneFrame(capturedAt: now.addingTimeInterval(2), sourceId: UUID(), jpeg: Data()))
        XCTAssertEqual(history.frames.count, 1)
        history.clear(); XCTAssertTrue(history.frames.isEmpty)
    }
    func testVoiceEndpointRetainsPrebufferAndRejectsShortNoise() {
        var vad = VoiceDetector()
        XCTAssertTrue(vad.process(Array(repeating: 0, count: 16000)).isEmpty)
        XCTAssertTrue(vad.process(Array(repeating: 0.3, count: 800)).isEmpty)
        XCTAssertTrue(vad.process(Array(repeating: 0, count: 800)).isEmpty)
        let started = vad.process(Array(repeating: 0.3, count: 3200))
        XCTAssertEqual(started.count, 1)
        guard case .started = started[0] else { return XCTFail("Expected speech onset") }
        XCTAssertTrue(vad.process(Array(repeating: 0, count: 10000)).isEmpty)
        let events = vad.process(Array(repeating: 0, count: 1200))
        guard case .completed(let samples) = events.first else { return XCTFail("Expected endpoint after 700 ms") }
        XCTAssertGreaterThan(samples.count, 11200)
    }
    func testVoiceLimitResetAndWAVFormat() {
        var vad = VoiceDetector()
        _ = vad.process(Array(repeating: 0, count: 16000))
        _ = vad.process(Array(repeating: 0.1, count: 2000))
        let events = vad.process(Array(repeating: 0.1, count: 320000))
        guard case .completed(let samples) = events.first else { return XCTFail("Expected 20-second cap") }
        XCTAssertEqual(samples.count, 320000)
        let wav = WAV.encode(samples)
        XCTAssertEqual(wav.count, 640044)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav[36..<40], encoding: .ascii), "data")
        vad.reset()
        XCTAssertTrue(vad.process(Array(repeating: 0.1, count: 1000)).isEmpty)
    }
}
