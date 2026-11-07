import Foundation

@main
struct CoreCheck {
    static func main() {
        let now = Date(), source = UUID()
        var history = SceneHistory()
        for index in 0...40 {
            history.append(SceneFrame(capturedAt: now.addingTimeInterval(Double(index - 40)), sourceId: source, jpeg: Data([1])))
        }
        let selected = history.selected(now: now)
        precondition(history.frames.count == 31 && selected.count == 6)
        precondition(selected.first?.capturedAt == now.addingTimeInterval(-30) && selected.last?.capturedAt == now)
        precondition(Set(selected.map(\.id)).count == 6 && history.selected(now: now.addingTimeInterval(3)).isEmpty)
        history.append(SceneFrame(capturedAt: now.addingTimeInterval(1), sourceId: UUID(), jpeg: Data()))
        precondition(history.frames.count == 1)
        var vad = VoiceDetector()
        precondition(vad.process(Array(repeating: 0, count: 16000)).isEmpty)
        precondition(vad.process(Array(repeating: 0.2, count: 800)).isEmpty)
        precondition(vad.process(Array(repeating: 0, count: 800)).isEmpty)
        let onset = vad.process(Array(repeating: 0.2, count: 3200))
        guard case .started = onset.first else { fatalError("Missing speech onset") }
        precondition(vad.process(Array(repeating: 0, count: 10000)).isEmpty)
        guard case .completed(let samples) = vad.process(Array(repeating: 0, count: 1200)).first else {
            fatalError("Missing 700 ms endpoint")
        }
        precondition(samples.count > 11200 && WAV.encode(samples).count == 44 + samples.count * 2)
        vad.reset()
        _ = vad.process(Array(repeating: 0, count: 16000))
        _ = vad.process(Array(repeating: 0.2, count: 3200))
        guard case .completed(let capped) = vad.process(Array(repeating: 0.2, count: 320000)).first else { fatalError("Missing duration limit") }
        precondition(capped.count == 320000 && WAV.encode(capped).count == 640044)
        precondition(String(data: WAV.encode(capped).prefix(4), encoding: .ascii) == "RIFF")
        print("PASS: frame selection, freshness, source reset, voice onset, silence endpoint, 20-second limit, WAV encoding")
    }
}
