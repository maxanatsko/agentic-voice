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
    private static let pathMarker = "__AGENTIC_VOICE_PATH__="

    /// A node binary the user chose by hand, tried before searching. Kept for this run only:
    /// the shared settings file is the app's only persisted setting.
    @MainActor static var chosenPath: String?

    /// The login shell's PATH, also used for the installer so it can find `claude`. Read from a
    /// marked line, because shell profiles may print banners of their own.
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

    /// `chosen` is a binary picked by hand; `path` is the login shell's PATH to search otherwise.
    static func locate(chosen: String?, path: String) throws -> NodeInstall {
        if let chosen {
            guard let install = inspect(chosen), isSupported(install) else { throw NodeLocatorError.unusable(chosen) }
            return install
        }
        var found: [NodeInstall] = []
        for candidate in candidates(path: path) where !found.contains(where: { $0.path == candidate }) {
            guard let install = inspect(candidate) else { continue }
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

    private static func candidates(path: String) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var directories = path.split(separator: ":").map(String.init)
        directories += ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.volta/bin"]
        let nvm = "\(home)/.nvm/versions/node"
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: nvm)) ?? []
        directories += versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }.map { "\(nvm)/\($0)/bin" }
        return directories.map { "\($0)/node" }
    }
}
