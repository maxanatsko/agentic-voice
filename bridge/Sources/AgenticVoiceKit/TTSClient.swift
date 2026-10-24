import Foundation

/// The TTS backend's HTTP contract: `GET /v1/audio/health` and `POST /v1/audio/synthesize`.
public struct TTSClient: Sendable {
    public enum Readiness: Sendable {
        case ready, initializing, unavailable, occupied
    }

    let baseURL: String
    let voice: String
    let language: String
    let speed: Double

    public init(baseURL: String, voice: String, language: String, speed: Double) {
        self.baseURL = baseURL
        self.voice = voice
        self.language = language
        self.speed = speed
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: RefuseRedirects(), delegateQueue: nil)
    }()

    private static func endpoint(_ baseURL: String, _ path: String) throws -> URL {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: base + path) else { throw AgenticVoiceError("Invalid TTS_URL: \(baseURL)") }
        return url
    }

    /// Readiness is optional for external URLs, required for automatic local startup.
    /// Throws only when the calling task is cancelled.
    public static func checkReadiness(_ baseURL: String) async throws -> Readiness {
        var request = URLRequest(url: try endpoint(baseURL, "/v1/audio/health"))
        request.timeoutInterval = 1
        do {
            let (data, response) = try await session.data(for: request)
            let status = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["status"] as? String
            switch ((response as? HTTPURLResponse)?.statusCode, status) {
            case (200, "ready"): return .ready
            case (503, "initializing"): return .initializing
            default: return .occupied
            }
        } catch {
            try Task.checkCancellation()
            return .unavailable
        }
    }

    public func synthesize(_ text: String) async throws -> Data {
        let boundary = "agentic-voice-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in [("language", language), ("text", text), ("voice", voice), ("speed", String(speed))] {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: try Self.endpoint(baseURL, "/v1/audio/synthesize"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // First synthesis after startup can be slow; MCP clients allow 360 seconds per tool call.
        request.timeoutInterval = 300
        let (data, response) = try await Self.session.upload(for: request, from: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw AgenticVoiceError("TTS request failed with HTTP \(status)\(detail.isEmpty ? "" : ": \(detail)")")
        }
        return data
    }
}

/// A redirect means the endpoint is not a TTS backend; report the redirect itself.
private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
