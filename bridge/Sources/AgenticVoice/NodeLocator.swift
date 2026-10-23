import Foundation

struct NodeInstall: Equatable, Sendable {
    let path: String
    let version: String
}

enum NodeLocatorError: Error, LocalizedError {
    case notFound
    case tooOld([NodeInstall])
    case unusable(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Node \(NodeLocator.minimumMajor)+ not found. Install it from nodejs.org or Homebrew, or choose a node binary."
        case .tooOld(let found):
            let list = found.map { "\($0.version) at \($0.path)" }.joined(separator: ", ")
            return "Node \(NodeLocator.minimumMajor)+ is required; found \(list). Upgrade, or choose a newer node binary."
        case .unusable(let path):
            return "\(path) is not a working Node \(NodeLocator.minimumMajor)+ binary."
        }
    }
}

/// Finds a Node 26+ binary. GUI apps don't inherit the shell's PATH, so this asks the login
/// shell for it and also checks the usual install locations.
enum NodeLocator {
    static let minimumMajor = 26
    private static let overrideKey = "nodePath"

    /// A node binary the user chose by hand, tried before searching.
    static var chosenPath: String? {
        get { UserDefaults.standard.string(forKey: overrideKey) }
        set { UserDefaults.standard.set(newValue, forKey: overrideKey) }
    }

    /// The login shell's PATH, also used for the installer so it can find `claude`.
    static func loginShellPath() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if let result = try? Shell.run(shell, ["-l", "-c", "printf %s \"$PATH\""], timeout: 5),
           result.status == 0, !result.stdout.isEmpty {
            return result.stdout
        }
        return ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
    }

    static func locate() throws -> NodeInstall {
        if let chosen = chosenPath {
            guard let install = inspect(chosen), isSupported(install) else { throw NodeLocatorError.unusable(chosen) }
            return install
        }
        var found: [NodeInstall] = []
        for path in candidates() where !found.contains(where: { $0.path == path }) {
            guard let install = inspect(path) else { continue }
            if isSupported(install) { return install }
            found.append(install)
        }
        throw found.isEmpty ? NodeLocatorError.notFound : NodeLocatorError.tooOld(found)
    }

    static func inspect(_ path: String) -> NodeInstall? {
        guard FileManager.default.isExecutableFile(atPath: path),
              let result = try? Shell.run(path, ["-p", "process.versions.node"], timeout: 10),
              result.status == 0
        else { return nil }
        return NodeInstall(path: path, version: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func isSupported(_ install: NodeInstall) -> Bool {
        (install.version.split(separator: ".").first.flatMap { Int($0) } ?? 0) >= minimumMajor
    }

    private static func candidates() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var directories = loginShellPath().split(separator: ":").map(String.init)
        directories += ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.volta/bin"]
        let nvm = "\(home)/.nvm/versions/node"
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: nvm)) ?? []
        directories += versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }.map { "\(nvm)/\($0)/bin" }
        return directories.map { "\($0)/node" }
    }
}
