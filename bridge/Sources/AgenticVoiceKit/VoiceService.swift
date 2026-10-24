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
        // Each chunk is synthesized while the one before it plays.
        let chunks = Self.chunk(prepared, limit: Self.chunkLimit)
        var next = Task { try await tts.synthesize(chunks[0]) }
        defer { next.cancel() }
        for index in chunks.indices {
            let wav = try await next.value
            if index + 1 < chunks.count {
                next = Task { try await tts.synthesize(chunks[index + 1]) }
            }
            try await player.play(wav)
        }
        return .spoken
    }

    /// Kokoro takes at most 510 phonemes per request (about 350 to 450 characters of English).
    static let chunkLimit = 320

    /// Sentences packed into chunks of at most `limit` characters; a longer sentence is split
    /// between words. Expects whitespace already normalized to single spaces.
    static func chunk(_ text: String, limit: Int) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            if let sentence = sentence?.trimmingCharacters(in: .whitespaces), !sentence.isEmpty { sentences.append(sentence) }
        }
        if sentences.isEmpty { sentences = [text] }

        var pieces: [String] = []
        for sentence in sentences {
            guard sentence.count > limit else { pieces.append(sentence); continue }
            var current = ""
            for word in sentence.split(separator: " ") {
                if !current.isEmpty && current.count + word.count + 1 > limit {
                    pieces.append(current)
                    current = ""
                }
                current += current.isEmpty ? String(word) : " " + word
            }
            if !current.isEmpty { pieces.append(current) }
        }

        var chunks: [String] = []
        for piece in pieces {
            if let last = chunks.last, last.count + piece.count + 1 <= limit {
                chunks[chunks.count - 1] = last + " " + piece
            } else {
                chunks.append(piece)
            }
        }
        return chunks
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
