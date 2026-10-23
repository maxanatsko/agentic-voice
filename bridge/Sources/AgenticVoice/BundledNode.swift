import Foundation

enum BundledNodeError: Error, LocalizedError {
    case notBundled

    var errorDescription: String? {
        "Node and the agentic-voice scripts aren't bundled with this copy of Agentic Voice; build it with npm run app:build."
    }
}

/// Runs scripts from the Node app that scripts/build-app.sh bundles, on the Node runtime bundled
/// beside them, so the app reuses the Node implementations of client config editing and speech
/// without asking users to install Node.
enum BundledNode {
    private static let pathMarker = "__AGENTIC_VOICE_PATH__="

    static var root: URL? {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("agentic-voice"),
              FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("node/bin/node").path),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("dist/src/cli.js").path)
        else { return nil }
        return root
    }

    /// The login shell's PATH, so the installer can find `claude`. GUI apps don't inherit it.
    /// Read from a marked line, because shell profiles may print banners of their own.
    static func loginShellPath() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if let result = try? Shell.run(shell, ["-l", "-c", "printf '\\n%s%s\\n' '\(pathMarker)' \"$PATH\""], timeout: 5),
           result.status == 0,
           let line = result.stdout.split(separator: "\n").last(where: { $0.hasPrefix(pathMarker) }),
           line.count > pathMarker.count {
            return String(line.dropFirst(pathMarker.count))
        }
        return ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
    }

    /// Blocking; call off the main actor. `path` is the login shell's PATH.
    static func run(_ script: String, _ arguments: [String], path: String, environment extra: [String: String] = [:]) throws -> Shell.Result {
        guard let root else { throw BundledNodeError.notBundled }
        let node = root.appendingPathComponent("node/bin/node").path
        var environment = ProcessInfo.processInfo.environment.merging(extra) { _, new in new }
        environment["PATH"] = path
        let script = root.appendingPathComponent("dist/src/\(script)").path
        return try Shell.run(node, [script] + arguments, environment: environment)
    }
}
