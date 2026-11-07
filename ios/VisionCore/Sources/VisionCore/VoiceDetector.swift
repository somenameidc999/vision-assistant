import Foundation

public enum VoiceEvent: Sendable {
    case started
    case completed([Float])
}

/// Operates on mono 16 kHz samples, off the audio render thread.
public struct VoiceDetector: Sendable {
    private let sampleRate = 16000
    private var calibrationSamples = 0
    private var calibrationEnergy: Double = 0
    private var threshold: Float = 0.01
    private var prebuffer: [Float] = []
    private var recording: [Float] = []
    private var active = false
    private var onsetSamples = 0
    private var silenceSamples = 0
    public init() {}
    public var detectionThreshold: Float { threshold }
    public var isRecording: Bool { active }
    public mutating func reset() { self = VoiceDetector() }
    public mutating func process(_ samples: [Float]) -> [VoiceEvent] {
        guard !samples.isEmpty else { return [] }
        let energy = samples.reduce(0.0) { $0 + Double($1 * $1) }
        if calibrationSamples < sampleRate {
            calibrationSamples += samples.count; calibrationEnergy += energy
            threshold = max(0.01, Float(sqrt(calibrationEnergy / Double(calibrationSamples))) * 3.5)
            return []
        }
        let voiced = Float(sqrt(energy / Double(samples.count))) > threshold
        if !active {
            prebuffer.append(contentsOf: samples)
            if prebuffer.count > 4800 { prebuffer.removeFirst(prebuffer.count - 4800) }
            onsetSamples = voiced ? onsetSamples + samples.count : 0
            if onsetSamples >= 1920 {
                active = true; recording = prebuffer; prebuffer.removeAll(keepingCapacity: true)
                silenceSamples = 0
                return [.started]
            }
            return []
        }
        recording.append(contentsOf: samples)
        silenceSamples = voiced ? 0 : silenceSamples + samples.count
        if silenceSamples >= 11200 || recording.count >= sampleRate * 20 {
            let result = Array(recording.prefix(sampleRate * 20))
            recording.removeAll(keepingCapacity: true); active = false; silenceSamples = 0; onsetSamples = 0
            return [.completed(result)]
        }
        return []
    }
}

public enum WAV {
    public static func encode(_ samples: [Float]) -> Data {
        let limited = samples.prefix(320000)
        var data = Data()
        func ascii(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) { var value = value.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var value = value.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        ascii("RIFF"); u32(UInt32(36 + limited.count * 2)); ascii("WAVEfmt ")
        u32(16); u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16)
        ascii("data"); u32(UInt32(limited.count * 2))
        for sample in limited {
            let clamped = sample.isFinite ? max(-1, min(1, sample)) : 0
            u16(UInt16(bitPattern: Int16(clamped * 32767)))
        }
        return data
    }
}
