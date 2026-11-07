import Foundation

/// Stores only backend session identifiers so app updates and crashes can clean up.
/// Captures, transcripts, answers, and credentials never enter this store.
@MainActor
public final class SessionRecoveryStore {
    private let defaults: UserDefaults
    private let key = "VisionAssistant.pendingBackendSessions"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func previous(for endpoint: String) -> UUID? {
        (defaults.dictionary(forKey: key)?[endpoint] as? String).flatMap(UUID.init(uuidString:))
    }
    public func record(_ id: UUID, for endpoint: String) {
        var records = defaults.dictionary(forKey: key) ?? [:]
        records[endpoint] = id.uuidString
        defaults.set(records, forKey: key)
    }
    public func clear(_ id: UUID, for endpoint: String) {
        // Late cleanup from an old session must not erase a newer session's record.
        guard previous(for: endpoint) == id else { return }
        var records = defaults.dictionary(forKey: key) ?? [:]
        records.removeValue(forKey: endpoint)
        defaults.set(records, forKey: key)
    }
}
