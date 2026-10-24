import AgenticVoiceKit
import Foundation

/// Speaks the arguments, or stdin when there are none. Returns the exit status: 75 (EX_TEMPFAIL)
/// when another session is speaking, so callers may retry later.
func speak(_ arguments: [String], environment: [String: String]) async throws -> Int32 {
    var text = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty {
        guard isatty(STDIN_FILENO) == 0 else { throw AgenticVoiceError("Provide text as arguments or pipe it through stdin.") }
        text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    }
    let voice = VoiceService(config: try Config.load(environment: environment))
    guard try await voice.speak(text) == .spoken else {
        printError("agentic-voice: another session is speaking; not spoken")
        return 75
    }
    return 0
}
