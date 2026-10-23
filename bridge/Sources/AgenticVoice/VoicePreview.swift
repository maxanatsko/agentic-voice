import AVFoundation
import TTSBridgeCore

enum VoicePreviewError: Error, LocalizedError {
    case busy
    case synthesis(String)

    var errorDescription: String? {
        switch self {
        case .busy: return "Another session is speaking; try again in a moment."
        case .synthesis(let message): return message
        }
    }
}

private struct ErrorBody: Decodable {
    let reason: String
}

/// Speaks a sample through the running bridge, holding the same speaking lock as agent sessions.
@MainActor
final class VoicePreview {
    private var player: AVAudioPlayer?

    func play(_ voice: Voice, speed: Double) async throws {
        guard let lock = PortLock.acquire(PortLock.speaking) else { throw VoicePreviewError.busy }
        defer { lock.release() }

        let wav = try await synthesize("Hi, I'm \(voice.name). This is how I sound.", voice: voice.id, speed: speed)
        let player = try AVAudioPlayer(data: wav)
        self.player = player
        player.play()
        try? await Task.sleep(for: .seconds(player.duration + 0.2))
        self.player = nil
    }

    private func synthesize(_ text: String, voice: String, speed: Double) async throws -> Data {
        let boundary = "agentic-voice-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in [("text", text), ("voice", voice), ("language", "en-US"), ("speed", String(speed))] {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(BridgeServer.port)/v1/audio/synthesize")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            // Vapor reports errors as {"error": true, "reason": "..."}.
            let reason = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.reason
            throw VoicePreviewError.synthesis(reason ?? String(decoding: data, as: UTF8.self))
        }
        return data
    }
}
