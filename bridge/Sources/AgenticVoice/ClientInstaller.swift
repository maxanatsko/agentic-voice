import AgenticVoiceKit
import Foundation

enum ClientInstallerError: Error, LocalizedError {
    case notBundled

    var errorDescription: String? {
        "The agentic-voice command and hooks aren't bundled with this copy of Agentic Voice; build it with scripts/build-app.sh."
    }
}

/// Installs agentic-voice into clients, pointing them at the agentic-voice command and hooks that
/// scripts/build-app.sh bundles under Contents/Resources/agentic-voice.
enum ClientInstaller {
    private static let pathMarker = "__AGENTIC_VOICE_PATH__="

    /// The bundled plugin root and its agentic-voice executable.
    private static func bundled() throws -> (root: URL, executable: URL) {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("agentic-voice") else { throw ClientInstallerError.notBundled }
        let executable = root.appendingPathComponent("bridge/.build/release/agentic-voice")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw ClientInstallerError.notBundled }
        return (root, executable)
    }

    /// The login shell's PATH, so the installer can find `claude`. GUI apps don't inherit it.
    /// Interactive as well as login, because version managers such as nvm usually extend PATH in
    /// ~/.zshrc or ~/.bashrc. Read from a marked line, because shell profiles may print banners.
    static func loginShellPath() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if let result = try? Shell.run(shell, ["-l", "-i", "-c", "printf '\\n%s%s\\n' '\(pathMarker)' \"$PATH\""], timeout: 10),
           result.status == 0,
           let line = result.stdout.split(separator: "\n").last(where: { $0.hasPrefix(pathMarker) }),
           line.count > pathMarker.count {
            return String(line.dropFirst(pathMarker.count))
        }
        return ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
    }

    /// Blocking; call off the main actor. `path` is the login shell's PATH.
    static func run(_ action: Clients.Action, clients: [String] = [], path: String) throws -> [ClientStatus] {
        let (root, executable) = try bundled()
        let context = InstallContext(home: NSHomeDirectory(), executable: executable.path, root: root.path, path: path)
        return try Clients.run(action, clients, context: context)
    }
}
