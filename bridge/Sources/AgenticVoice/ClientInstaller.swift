import Foundation

/// One row of `install-clients` output (src/install-clients.ts).
struct ClientStatus: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let detected: Bool
    let installed: Bool
    let current: Bool
    let note: String?
    let error: String?
}

enum ClientInstallerError: Error, LocalizedError {
    case notBundled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notBundled:
            return "The MCP server isn't bundled with this copy of the app; build it with npm run app:build."
        case .failed(let message):
            return message
        }
    }
}

/// Runs the bundled Node installer, which owns all client config editing.
enum ClientInstaller {
    /// The repository layout copied into the app by scripts/build-app.sh.
    static var pluginRoot: URL? {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("agentic-voice"),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("dist/src/install-clients.js").path)
        else { return nil }
        return root
    }

    static func run(_ command: String, clients: [String] = [], node: NodeInstall, path: String) throws -> [ClientStatus] {
        guard let root = pluginRoot else { throw ClientInstallerError.notBundled }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = path
        let script = root.appendingPathComponent("dist/src/install-clients.js").path
        let result = try Shell.run(node.path, [script, command] + clients, environment: environment)
        // Per-client failures still print every status (with an error) and exit 1.
        if let statuses = try? JSONDecoder().decode([ClientStatus].self, from: Data(result.stdout.utf8)) {
            return statuses
        }
        throw ClientInstallerError.failed(result.stderr.isEmpty ? "install-clients exited with \(result.status)" : result.stderr)
    }
}
