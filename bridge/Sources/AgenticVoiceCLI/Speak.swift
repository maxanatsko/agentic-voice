import AgenticVoiceKit
import Foundation

/// The kinds, for messages: "question, completion, alert, custom".
let speechKinds = SpeechKind.allCases.map(\.rawValue).joined(separator: ", ")

/// Speaks the arguments, or stdin when there are none, after an optional leading `--kind <kind>`;
/// `--` ends the options, for text that starts with "--kind". Returns the exit status: 75
/// (EX_TEMPFAIL) when another session is speaking, so callers may retry later.
func speak(_ arguments: [String], environment: [String: String]) async throws -> Int32 {
    var arguments = arguments[...]
    var kind: SpeechKind?
    if arguments.first == "--kind" {
        guard let value = arguments.dropFirst().first, let parsed = SpeechKind(rawValue: value) else {
            throw AgenticVoiceError("--kind must be one of: \(speechKinds).")
        }
        kind = parsed
        arguments = arguments.dropFirst(2)
    }
    if arguments.first == "--" { arguments = arguments.dropFirst() }
    var text = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty {
        guard isatty(STDIN_FILENO) == 0 else { throw AgenticVoiceError("Provide text as arguments or pipe it through stdin.") }
        text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    }
    let voice = VoiceService(config: try Config.load(environment: environment))
    guard try await voice.speak(text, kind: kind) == .spoken else {
        printError("agentic-voice: another session is speaking; not spoken")
        return 75
    }
    return 0
}
