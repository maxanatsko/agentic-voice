import Foundation

enum BundledNodeError: Error, LocalizedError {
    case notBundled

    var errorDescription: String? {
        "The agentic-voice Node app isn't bundled with this copy of Agentic Voice; build it with npm run app:build."
    }
}

/// Runs scripts from the Node app that scripts/build-app.sh bundles, so the app reuses the Node
/// implementations of client config editing and speech instead of duplicating them.
enum BundledNode {
    static var root: URL? {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("agentic-voice"),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("dist/src/cli.js").path)
        else { return nil }
        return root
    }

    /// Blocking; call off the main actor. `path` is the login shell's PATH.
    static func run(_ script: String, _ arguments: [String], node: NodeInstall, path: String, environment extra: [String: String] = [:]) throws -> Shell.Result {
        guard let root else { throw BundledNodeError.notBundled }
        var environment = ProcessInfo.processInfo.environment.merging(extra) { _, new in new }
        environment["PATH"] = path
        let script = root.appendingPathComponent("dist/src/\(script)").path
        return try Shell.run(node.path, [script] + arguments, environment: environment)
    }
}
