import AgenticVoiceKit
import Foundation

/// Prints one JSON status per client on stdout; failures carry an error and set the exit status.
func runClients(_ arguments: [String], context: InstallContext) throws -> Int32 {
    guard let command = arguments.first, let action = Clients.Action(rawValue: command) else {
        throw AgenticVoiceError(usage)
    }
    let names = Array(arguments.dropFirst())
    if action != .status && names.isEmpty { throw AgenticVoiceError("Name the clients to \(command).\n\(usage)") }
    if let unknown = names.first(where: { !Clients.ids.contains($0) }) {
        throw AgenticVoiceError("Unknown client '\(unknown)'.\n\(usage)")
    }

    let results = try Clients.run(action, names, context: context)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(results), as: UTF8.self))
    return results.contains { $0.error != nil } ? 1 : 0
}
