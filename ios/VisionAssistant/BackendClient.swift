import Foundation
import VisionCore

struct LocalConfiguration: Codable {
    var backendURL: String = "http://localhost:18787"
    var sessionToken: String = ""
    static func load() -> Self {
        guard let url = Bundle.main.url(forResource: "LocalConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url), let config = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return config
    }
}
struct TurnReply: Decodable {
    let turnId: UUID
    let transcript: String
    let answer: String
    let model: String
    let usage: Usage
    let timing: Timing
    let budget: BudgetInfo
    struct Usage: Decodable { let inputTokens: Int; let outputTokens: Int; let costUSD: Double? }
    struct Timing: Decodable { let providerMs: Int; let newestFrameAgeAtResponseMs: Int }
}
struct BudgetInfo: Decodable { let limitUSD: Double; let accountedUSD: Double }
private struct SessionReply: Decodable { let sessionId: UUID; let budget: BudgetInfo; let serverTime: String? }
private struct ServiceError: Decodable { let error: ErrorBody; struct ErrorBody: Decodable { let code: String; let message: String } }
struct DemoError: LocalizedError {
    let message: String
    let code: String?
    init(message: String, code: String? = nil) { self.message = message; self.code = code }
    var errorDescription: String? { message }
}

private final class BackendRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Camera and microphone data must stay on the configured backend route.
        completionHandler(nil)
    }
}

@MainActor
final class BackendClient {
    private let config: LocalConfiguration
    private let session: URLSession
    private let recovery = SessionRecoveryStore()
    private var serverClockOffset: TimeInterval = 0
    init(config: LocalConfiguration) {
        self.config = config
        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = 32
        settings.urlCache = nil
        session = URLSession(configuration: settings, delegate: BackendRedirectPolicy(), delegateQueue: nil)
    }
    private func request(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        guard let base = URL(string: config.backendURL), let scheme = base.scheme,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              ["http", "https"].contains(scheme), let host = base.host,
              ["localhost", "127.0.0.1", "::1"].contains(host) || host.hasSuffix(".local")
                || (scheme == "https" && host.hasSuffix(".ts.net")) || BackendAddress.isPrivateIPv4(host) else {
            throw DemoError(message: "Use localhost for Simulator, your Mac’s private Wi-Fi IPv4 address or .local hostname, or a private Tailscale HTTPS address ending in .ts.net.")
        }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(config.sessionToken)", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DemoError(message: "No backend response.") }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(ServiceError.self, from: data)
            throw DemoError(message: error?.error.message ?? "Backend request failed (\(http.statusCode)).", code: error?.error.code)
        }
        return data
    }
    func start() async throws -> UUID {
        if let previous = recovery.previous(for: config.backendURL) {
            _ = try await request("DELETE", "v1/sessions/\(previous.uuidString.lowercased())")
            recovery.clear(previous, for: config.backendURL)
        }
        let sentAt = Date()
        let data = try await request("POST", "v1/sessions")
        let receivedAt = Date()
        let reply = try JSONDecoder().decode(SessionReply.self, from: data)
        if let serverTime = reply.serverTime,
           let offset = SceneTimestamp.clockOffset(serverTime: serverTime, sentAt: sentAt, receivedAt: receivedAt) {
            serverClockOffset = offset
        }
        recovery.record(reply.sessionId, for: config.backendURL)
        return reply.sessionId
    }
    func turn(sessionId: UUID, turnId: UUID, text: String?, audio: Data?, frames: [SceneFrame]) async throws -> TurnReply {
        struct Payload: Encodable {
            let turnId: UUID; let text: String?; let audio: Audio?; let frames: [SceneFrame]
            struct Audio: Encodable { let format = "wav"; let data: Data }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SceneTimestamp.encode(date))
        }
        let alignedFrames = frames.map { frame in
            SceneFrame(id: frame.id, capturedAt: frame.capturedAt.addingTimeInterval(serverClockOffset),
                       sourceId: frame.sourceId, playbackSeconds: frame.playbackSeconds, jpeg: frame.jpeg)
        }
        let body = try encoder.encode(Payload(turnId: turnId, text: text,
            audio: audio.map { Payload.Audio(data: $0) }, frames: alignedFrames))
        return try JSONDecoder().decode(TurnReply.self, from: await request("POST", "v1/sessions/\(sessionId.uuidString.lowercased())/turns", body: body))
    }
    func cancel(sessionId: UUID, turnId: UUID) async {
        let data = try? JSONEncoder().encode(["turnId": turnId.uuidString])
        _ = try? await request("POST", "v1/sessions/\(sessionId.uuidString.lowercased())/cancel", body: data)
    }
    func end(sessionId: UUID) async {
        do {
            _ = try await request("DELETE", "v1/sessions/\(sessionId.uuidString.lowercased())")
            recovery.clear(sessionId, for: config.backendURL)
        } catch { /* Keep the identifier so the next start retries cleanup. */ }
    }
}
