import AgenticVoiceKit
import Foundation
import TTSBridgeCore

enum VoicePreviewError: Error, LocalizedError {
    case busy

    var errorDescription: String? {
        "Another session is speaking; try again in a moment."
    }
}

/// Speaks a sample through the same VoiceService agents use: the same TTS client, the same
/// speaking lock, the same playback.
enum VoicePreview {
    static func play(_ voice: Voice, speed: Double) async throws {
        var config = try Config.load()
        config.voice = voice.id
        config.speed = speed
        if try await VoiceService(config: config).speak("Hi, I'm \(voice.name). This is how I sound.") == .busy {
            throw VoicePreviewError.busy
        }
    }
}
