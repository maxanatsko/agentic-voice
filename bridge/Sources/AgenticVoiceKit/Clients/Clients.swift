import Foundation

/// Where the installer runs from: the home directory, the agentic-voice executable, the plugin
/// root (hooks and the opencode plugin), and the PATH used to find the `claude` CLI.
public struct InstallContext: Sendable {
    public var home: String
    public var executable: String
    public var root: String
    public var path: String?

    public init(home: String, executable: String, root: String, path: String? = nil) {
        self.home = home
        self.executable = executable
        self.root = root
        self.path = path
    }
}

public struct ClientStatus: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let detected: Bool
    public let installed: Bool
    public let current: Bool
    public let note: String?
    public var error: String?
}

/// Writes agentic-voice entries into each client's user-level config files.
public enum Clients {
    public static let ids = ["claude-code", "claude-desktop", "codex", "cursor", "vscode", "windsurf", "opencode"]

    private static let name = "agentic-voice"
    private static let managedPlugin = "// Managed by Agentic Voice: speaks when opencode finishes or needs your input."

    private enum Part {
        case json(file: String, container: String, entry: Any)
        case hook(file: String, event: String, command: String)
        case toml(file: String, table: String, body: String)
        case file(file: String, content: String)
        case claudeCLI(file: String, entry: [String: Any])
    }

    private struct Client {
        let id: String
        let name: String
        let directory: String
        let parts: [Part]
        var note: String?
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func join(_ base: String, _ path: String) -> String {
        (base as NSString).appendingPathComponent(path)
    }

    private static func clients(_ context: InstallContext) -> [Client] {
        let home = context.home
        let command = context.executable
        let args = ["mcp"]
        let hook = "\(shellQuote(join(context.root, "hooks/speak-notify.sh"))) input \(ConfigEdit.hookMarker)"
        let appSupport = join(home, "Library/Application Support")
        let opencodeDir = join(home, ".config/opencode")
        let opencodeJSONC = join(opencodeDir, "opencode.jsonc")
        let pluginURL = URL(fileURLWithPath: join(context.root, "opencode/plugin.mjs")).absoluteString
        return [
            Client(id: "claude-code", name: "Claude Code", directory: join(home, ".claude"), parts: [
                .claudeCLI(file: join(home, ".claude.json"), entry: ["command": command, "args": args]),
                .hook(file: join(home, ".claude/settings.json"), event: "Notification", command: hook),
            ]),
            Client(id: "claude-desktop", name: "Claude Desktop", directory: join(appSupport, "Claude"), parts: [
                .json(file: join(appSupport, "Claude/claude_desktop_config.json"), container: "mcpServers", entry: ["command": command, "args": args]),
            ]),
            Client(id: "codex", name: "Codex CLI", directory: join(home, ".codex"), parts: [
                .toml(
                    file: join(home, ".codex/config.toml"), table: "mcp_servers.\(name)",
                    body: "command = \(ConfigEdit.jsonString(command))\nargs = [\(ConfigEdit.jsonString("mcp"))]\ntool_timeout_sec = 360\n"
                ),
                .hook(file: join(home, ".codex/hooks.json"), event: "PermissionRequest", command: hook),
            ], note: "Restart Codex, then trust the new hook with /hooks."),
            Client(id: "cursor", name: "Cursor", directory: join(home, ".cursor"), parts: [
                .json(file: join(home, ".cursor/mcp.json"), container: "mcpServers", entry: ["command": command, "args": args]),
            ]),
            Client(id: "vscode", name: "VS Code", directory: join(appSupport, "Code"), parts: [
                .json(file: join(appSupport, "Code/User/mcp.json"), container: "servers", entry: ["type": "stdio", "command": command, "args": args]),
            ]),
            Client(id: "windsurf", name: "Windsurf", directory: join(home, ".codeium/windsurf"), parts: [
                .json(file: join(home, ".codeium/windsurf/mcp_config.json"), container: "mcpServers", entry: ["command": command, "args": args]),
            ]),
            Client(id: "opencode", name: "opencode", directory: opencodeDir, parts: [
                .json(
                    file: FileManager.default.fileExists(atPath: opencodeJSONC) ? opencodeJSONC : join(opencodeDir, "opencode.json"),
                    container: "mcp", entry: ["type": "local", "command": [command] + args, "enabled": true] as [String: Any]
                ),
                .file(
                    file: join(opencodeDir, "plugins/\(name).js"),
                    content: "\(managedPlugin)\nexport * from \(ConfigEdit.jsonString(pluginURL));\n"
                ),
            ]),
        ]
    }

    private static func read(_ file: String) throws -> String? {
        guard FileManager.default.fileExists(atPath: file) else { return nil }
        return try String(contentsOfFile: file, encoding: .utf8)
    }

    /// Backs up the original once, then replaces the file atomically, keeping its permissions.
    private static func write(_ file: String, _ next: String, previous: String?) throws {
        if next == previous { return }
        let manager = FileManager.default
        try manager.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let backup = "\(file).\(name)-backup"
        if previous != nil && !manager.fileExists(atPath: backup) { try manager.copyItem(atPath: file, toPath: backup) }
        let temporary = "\(file).\(name)-tmp"
        try? manager.removeItem(atPath: temporary)
        guard manager.createFile(atPath: temporary, contents: Data(next.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw AgenticVoiceError("Cannot write \(temporary).")
        }
        if previous != nil, let mode = try manager.attributesOfItem(atPath: file)[.posixPermissions] as? NSNumber {
            try manager.setAttributes([.posixPermissions: mode.intValue & 0o777], ofItemAtPath: temporary)
        }
        guard rename(temporary, file) == 0 else {
            throw AgenticVoiceError("Cannot replace \(file): \(String(cString: strerror(errno)))")
        }
    }

    private static func claude(_ args: [String], context: InstallContext) throws {
        var environment = ProcessInfo.processInfo.environment
        if let path = context.path { environment["PATH"] = path }
        let result = try Shell.run("/usr/bin/env", ["claude"] + args, environment: environment)
        guard result.status != 0 else { return }
        let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        // env exits 127 when it can't find the program.
        let reason = result.status == 127 && detail.hasPrefix("env:")
            ? "the Claude Code CLI 'claude' was not found on PATH"
            : (detail.isEmpty ? "exit status \(result.status)" : detail)
        throw AgenticVoiceError("claude \(args.prefix(2).joined(separator: " ")) failed: \(reason)")
    }

    /// Returns (installed, current) for one part.
    private static func inspect(_ part: Part) throws -> (Bool, Bool) {
        switch part {
        case .json(let file, let container, let entry):
            guard let text = try read(file) else { return (false, false) }
            let existing = try ConfigEdit.readJSONEntry(text, path: file, container: container, name: name)
            return (existing != nil, ConfigEdit.jsonEqual(existing, entry))
        case .claudeCLI(let file, let entry):
            guard let text = try read(file) else { return (false, false) }
            let existing = try ConfigEdit.readJSONEntry(text, path: file, container: "mcpServers", name: name) as? [String: Any]
            return (existing != nil, ConfigEdit.jsonEqual(existing?["command"], entry["command"]) && ConfigEdit.jsonEqual(existing?["args"], entry["args"]))
        case .hook(let file, let event, let command):
            guard let text = try read(file) else { return (false, false) }
            let existing = try ConfigEdit.readHookCommand(text, path: file, event: event)
            return (existing != nil, existing == command)
        case .toml(let file, let table, let body):
            guard let text = try read(file) else { return (false, false) }
            let block = try ConfigEdit.readTOMLBlock(text)
            return (block != nil, block == ConfigEdit.tomlBlock(table: table, body: body))
        case .file(let file, let content):
            guard let text = try read(file) else { return (false, false) }
            return (text.hasPrefix(managedPlugin), text == content)
        }
    }

    /// Computes a part's edit, throwing if it must be refused, and returns the step that applies it.
    private static func prepareInstall(_ part: Part, context: InstallContext) throws -> () throws -> Void {
        switch part {
        case .json(let file, let container, let entry):
            let text = try read(file)
            let next = try ConfigEdit.upsertJSONEntry(text ?? "", path: file, container: container, name: name, entry: entry)
            return { try write(file, next, previous: text) }
        case .claudeCLI(let file, let entry):
            let replace = try read(file).map { try ConfigEdit.readJSONEntry($0, path: file, container: "mcpServers", name: name) != nil } ?? false
            var stdio = entry
            stdio["type"] = "stdio"
            let json = try ConfigEdit.render(stdio).trimmingCharacters(in: .whitespacesAndNewlines)
            return {
                if replace { try claude(["mcp", "remove", "-s", "user", name], context: context) }
                try claude(["mcp", "add-json", "-s", "user", name, json], context: context)
            }
        case .hook(let file, let event, let command):
            let text = try read(file)
            let next = try ConfigEdit.upsertHook(text ?? "", path: file, event: event, command: command)
            return { try write(file, next, previous: text) }
        case .toml(let file, let table, let body):
            let text = try read(file)
            let next = try ConfigEdit.upsertTOMLBlock(text ?? "", path: file, table: table, body: body)
            return { try write(file, next, previous: text) }
        case .file(let file, let content):
            let text = try read(file)
            if let text, !text.hasPrefix(managedPlugin) {
                throw AgenticVoiceError("\(file) exists and was not written by Agentic Voice; move it aside, then install again.")
            }
            return { try write(file, content, previous: text) }
        }
    }

    private static func uninstall(_ part: Part, context: InstallContext) throws {
        switch part {
        case .json(let file, let container, _):
            guard let text = try read(file) else { return }
            try write(file, ConfigEdit.removeJSONEntry(text, path: file, container: container, name: name), previous: text)
        case .claudeCLI(let file, _):
            guard let text = try read(file) else { return }
            if try ConfigEdit.readJSONEntry(text, path: file, container: "mcpServers", name: name) != nil {
                try claude(["mcp", "remove", "-s", "user", name], context: context)
            }
        case .hook(let file, let event, _):
            guard let text = try read(file) else { return }
            try write(file, ConfigEdit.removeHook(text, path: file, event: event), previous: text)
        case .toml(let file, _, _):
            guard let text = try read(file) else { return }
            try write(file, ConfigEdit.removeTOMLBlock(text), previous: text)
        case .file(let file, _):
            guard let text = try read(file), text.hasPrefix(managedPlugin) else { return }
            try FileManager.default.removeItem(atPath: file)
        }
    }

    private static func find(_ context: InstallContext, _ id: String) throws -> Client {
        guard let client = clients(context).first(where: { $0.id == id }) else {
            throw AgenticVoiceError("Unknown client '\(id)'.")
        }
        return client
    }

    /// An agentic-voice Claude Code plugin would register the same tool and hooks a second time.
    private static func conflict(_ context: InstallContext, _ client: Client) throws -> String? {
        guard client.id == "claude-code", let settings = try read(join(context.home, ".claude/settings.json")) else { return nil }
        let root = try ConfigEdit.parseObject(settings, path: join(context.home, ".claude/settings.json"), snippet: [:] as [String: Any])
        let enabled = root["enabledPlugins"] as? [String: Any] ?? [:]
        let both = enabled.contains { plugin, on in plugin.hasPrefix("\(name)@") && (on as? Bool ?? false) }
        return both ? "The agentic-voice Claude Code plugin is also enabled; disable one of them to avoid speaking twice." : nil
    }

    public static func status(_ context: InstallContext, _ id: String) throws -> ClientStatus {
        let client = try find(context, id)
        var parts: [(Bool, Bool)]
        var note: String?
        do {
            parts = try client.parts.map(inspect)
            note = try conflict(context, client) ?? client.note
        } catch {
            parts = [(false, false)]
            note = error.localizedDescription
        }
        return ClientStatus(
            id: id, name: client.name,
            detected: FileManager.default.fileExists(atPath: client.directory),
            installed: parts.allSatisfy(\.0),
            current: parts.allSatisfy(\.1),
            note: note
        )
    }

    /// Checks every part before writing any, so a refused part leaves the client untouched.
    public static func install(_ context: InstallContext, _ id: String) throws {
        let steps = try find(context, id).parts.map { try prepareInstall($0, context: context) }
        for apply in steps { try apply() }
    }

    public static func uninstall(_ context: InstallContext, _ id: String) throws {
        for part in try find(context, id).parts { try uninstall(part, context: context) }
    }

    public enum Action: String, Sendable {
        case status, install, uninstall
    }

    /// Applies the action to each client (every client when none is named) and reports their
    /// statuses; a client the action failed for carries the failure in `error`.
    public static func run(_ action: Action, _ ids: [String], context: InstallContext) throws -> [ClientStatus] {
        try (ids.isEmpty ? Self.ids : ids).map { id in
            var failure: String?
            do {
                switch action {
                case .status: break
                case .install: try install(context, id)
                case .uninstall: try uninstall(context, id)
                }
            } catch {
                failure = error.localizedDescription
            }
            var result = try status(context, id)
            result.error = failure
            return result
        }
    }
}
