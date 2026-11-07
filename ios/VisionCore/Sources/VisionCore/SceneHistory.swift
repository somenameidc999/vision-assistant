import Foundation

public struct SceneFrame: Codable, Identifiable, Sendable {
    public let id: UUID
    public let capturedAt: Date
    public let sourceId: UUID
    public let playbackSeconds: Double?
    public let jpeg: Data
    public init(id: UUID = UUID(), capturedAt: Date = Date(), sourceId: UUID,
                playbackSeconds: Double? = nil, jpeg: Data) {
        self.id = id; self.capturedAt = capturedAt; self.sourceId = sourceId
        self.playbackSeconds = playbackSeconds; self.jpeg = jpeg
    }
}

public struct SceneHistory: Sendable {
    public private(set) var frames: [SceneFrame] = []
    public init() {}
    public mutating func clear() { frames.removeAll() }
    public mutating func append(_ frame: SceneFrame) {
        if let previous = frames.last,
           previous.sourceId != frame.sourceId || frame.capturedAt <= previous.capturedAt
            || (frame.playbackSeconds != nil && previous.playbackSeconds != nil
                && frame.playbackSeconds! < previous.playbackSeconds!) {
            clear()
        }
        frames.append(frame)
        frames.removeAll { frame.capturedAt.timeIntervalSince($0.capturedAt) > 30 }
        // Allow question-time refreshes alongside the regular one-frame-per-second history.
        if frames.count > 64 { frames.removeFirst(frames.count - 64) }
    }
    public func selected(now: Date = Date()) -> [SceneFrame] {
        let valid = frames.filter { now.timeIntervalSince($0.capturedAt) <= 30 && now.timeIntervalSince($0.capturedAt) >= -1 }
        guard let newest = valid.last, now.timeIntervalSince(newest.capturedAt) <= 2 else { return [] }
        guard valid.count > 6 else { return valid }
        return (0..<6).map { valid[Int((Double($0) * Double(valid.count - 1) / 5).rounded())] }
    }
}


public enum SceneTimestamp {
    public static func encode(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    public static func decode(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    public static func clockOffset(serverTime: String, sentAt: Date, receivedAt: Date) -> TimeInterval? {
        let roundTrip = receivedAt.timeIntervalSince(sentAt)
        guard (0...5).contains(roundTrip), let server = decode(serverTime) else { return nil }
        return server.timeIntervalSince(sentAt.addingTimeInterval(roundTrip / 2))
    }
}
