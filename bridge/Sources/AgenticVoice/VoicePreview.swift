import Foundation
import TTSBridgeCore

enum VoicePreviewError: Error, LocalizedError {
    case busy
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .busy: return "Another session is speaking; try again in a moment."
        case .failed(let message): return message
        }
    }
}

/// Speaks a sample through the bundled CLI, so a preview takes exactly the path agent speech
/// does: the same TTS client, the same speaking lock, the same playback.
enum VoicePreview {
    /// Blocking; call off the main actor.
    static func play(_ voice: Voice, speed: Double, path: String) throws {
        let result = try BundledNode.run(
            "cli.js", ["Hi, I'm \(voice.name). This is how I sound."],
            path: path,
            environment: ["TTS_VOICE": voice.id, "VOICE_SPEED": String(speed)]
        )
        switch result.status {
        case 0: return
        case 75: throw VoicePreviewError.busy  // EX_TEMPFAIL from src/cli.ts
        default:
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            // A timeout or signal kills the CLI before it can explain itself.
            throw VoicePreviewError.failed(stderr.isEmpty ? "The preview stopped without an error (exit status \(result.status)); try again." : stderr)
        }
    }
}
