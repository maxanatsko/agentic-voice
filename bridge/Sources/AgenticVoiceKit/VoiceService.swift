import Foundation

/// The speak use case, shared by MCP, the CLI and the app's voice preview.
public struct VoiceService: Sendable {
    public enum Outcome: Sendable {
        case spoken, busy
    }

    let tts: TTSClient
    let player: AudioPlayer
    let maxChars: Int

    public init(tts: TTSClient, player: AudioPlayer, maxChars: Int) {
        self.tts = tts
        self.player = player
        self.maxChars = maxChars
    }

    public init(config: AppConfig) {
        self.init(
            tts: TTSClient(baseURL: config.ttsURL, voice: config.voice, language: config.language, speed: config.speed),
            player: AudioPlayer(command: config.playbackCommand ?? "afplay"),
            maxChars: config.maxChars
        )
    }

    /// Speaks, or returns `.busy` without synthesizing when another session holds the speaker.
    public func speak(_ text: String) async throws -> Outcome {
        let prepared = try Self.prepareSpeechText(text, maxChars: maxChars)
        guard let claim = try player.claim() else { return .busy }
        defer { claim.release() }
        // Holding the claim through synthesis keeps another session from cutting in before playback.
        let wav = try await tts.synthesize(prepared)
        try await player.play(wav)
        return .spoken
    }

    public static func prepareSpeechText(_ text: String, maxChars: Int) throws -> String {
        let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !normalized.isEmpty else { throw AgenticVoiceError("Spoken text cannot be empty.") }
        guard normalized.count <= maxChars else {
            throw AgenticVoiceError("Spoken text is \(normalized.count) characters; limit is \(maxChars). Summarize before speaking.")
        }
        return normalized
    }
}
