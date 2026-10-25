import AgenticVoiceKit
import Foundation

/// This executable as the OS launched it, so a PATH lookup is resolved. A symlink to the
/// executable itself (say, on PATH) is followed, but not the .build/release directory symlink:
/// the plugin root is four levels up from <root>/bridge/.build/release/agentic-voice, both in
/// a checkout and inside the app bundle.
let executable: URL = {
    var size = UInt32(PATH_MAX)
    var buffer = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buffer, &size) == 0 else { fail("cannot locate the agentic-voice executable") }
    var url = URL(fileURLWithPath: String(cString: buffer)).standardizedFileURL
    if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
        url = URL(fileURLWithPath: target, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
    }
    return url
}()
let pluginRoot = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// The environment, plus `.env` from the plugin root. Existing variables take precedence.
func environment() -> [String: String] {
    let environment = ProcessInfo.processInfo.environment
    guard let text = try? String(contentsOf: pluginRoot.appendingPathComponent(".env"), encoding: .utf8) else { return environment }
    return Config.parseDotEnv(text).merging(environment) { _, existing in existing }
}

func fail(_ message: String) -> Never {
    printError("agentic-voice: \(message)")
    exit(1)
}

let usage = """
    usage: agentic-voice mcp
           agentic-voice speak [--kind <kind>] [--] <text...>   (or text on stdin)
           agentic-voice clients status [client...]
           agentic-voice clients <install|uninstall> <client...>
    kinds: \(speechKinds)
    clients: \(Clients.ids.joined(separator: ", "))
    """

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    switch arguments.first {
    case "mcp":
        try await runMCPServer(environment: environment(), bridgeExecutable: executable.deletingLastPathComponent().appendingPathComponent("TTSBridge"))
    case "speak":
        exit(try await speak(Array(arguments.dropFirst()), environment: environment()))
    case "clients":
        let context = InstallContext(home: NSHomeDirectory(), executable: executable.path, root: pluginRoot.path)
        exit(try runClients(Array(arguments.dropFirst()), context: context))
    default:
        fail(usage)
    }
} catch {
    fail(error.localizedDescription)
}
