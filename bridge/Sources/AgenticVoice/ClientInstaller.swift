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
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

/// Runs the bundled Node installer, which owns all client config editing.
enum ClientInstaller {
    static func run(_ command: String, clients: [String] = [], node: NodeInstall, path: String) throws -> [ClientStatus] {
        let result = try BundledNode.run("install-clients.js", [command] + clients, node: node, path: path)
        // Per-client failures still print every status (with an error) and exit 1.
        if let statuses = try? JSONDecoder().decode([ClientStatus].self, from: Data(result.stdout.utf8)) {
            return statuses
        }
        throw ClientInstallerError.failed(result.stderr.isEmpty ? "install-clients exited with \(result.status)" : result.stderr)
    }
}
