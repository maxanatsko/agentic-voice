@testable import AgenticVoiceKit
import Foundation
import Testing

private let root = "/Applications/Agentic Voice.app/Contents/Resources/agentic-voice"
private let executable = "\(root)/bridge/.build/release/agentic-voice"
private let hook = "'\(root)/hooks/speak-notify.sh' input # managed by agentic-voice"

/// A temporary home with a fake `claude` CLI that edits ~/.claude.json like the real one.
final class ClientsFixture {
    let home: TemporaryDirectory
    let context: InstallContext

    init() throws {
        home = try TemporaryDirectory()
        let config = home.path(".claude.json")
        try home.write("bin/claude", """
            #!/bin/bash
            # claude mcp <add-json|remove> -s user <name> [json]
            [ -f '\(config)' ] || echo '{"mcpServers":{}}' > '\(config)'
            plutil -extract mcpServers json -o - '\(config)' >/dev/null 2>&1 || plutil -insert mcpServers -json '{}' '\(config)'
            if [ "$2" = add-json ]; then plutil -insert "mcpServers.$5" -json "$6" '\(config)'
            else plutil -remove "mcpServers.$5" '\(config)'; fi
            """, mode: 0o755)
        context = InstallContext(
            home: home.url.path, executable: executable, root: root,
            path: "\(home.path("bin")):/usr/bin:/bin"
        )
    }

    func json(_ path: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(home.read(path).utf8)) as! [String: Any]
    }

    func installAll(_ context: InstallContext? = nil) throws {
        for id in Clients.ids { try Clients.install(context ?? self.context, id) }
    }
}

private let existing = [
    ".cursor/mcp.json": #"{"mcpServers":{"other":{"command":"other"}},"theme":"dark"}"#,
    ".claude/settings.json": #"{"hooks":{"Notification":[{"hooks":[{"type":"command","command":"say hi"}]}]},"model":"opus"}"#,
    ".codex/config.toml": "model = \"gpt\"\n\n[mcp_servers.other]\ncommand = \"other\"\n",
]

private func equal(_ a: Any?, _ b: Any?) -> Bool {
    ConfigEdit.jsonEqual(a, b)
}

struct ClientsTests {
    @Test func installsEveryClientKeepingExistingEntries() throws {
        let f = try ClientsFixture()
        for (path, content) in existing { try f.home.write(path, content) }
        try f.installAll()

        for id in Clients.ids {
            let status = try Clients.status(f.context, id)
            #expect(status.installed, "\(id)")
            #expect(status.current, "\(id)")
        }

        let cursor = try f.json(".cursor/mcp.json")
        let servers = cursor["mcpServers"] as? [String: Any]
        #expect(equal(servers?["other"], ["command": "other"]))
        #expect(equal(servers?["agentic-voice"], ["command": executable, "args": ["mcp"]]))
        #expect(cursor["theme"] as? String == "dark")

        let claude = try f.json(".claude.json")
        #expect(equal((claude["mcpServers"] as? [String: Any])?["agentic-voice"], ["type": "stdio", "command": executable, "args": ["mcp"]]))
        let settings = try f.json(".claude/settings.json")
        #expect(settings["model"] as? String == "opus")
        let notification = (settings["hooks"] as? [String: Any])?["Notification"] as? [[String: Any]]
        #expect(notification?.count == 2)
        #expect(((notification?.last?["hooks"] as? [[String: Any]])?.first?["command"] as? String) == hook)

        let toml = try f.home.read(".codex/config.toml")
        #expect(toml.hasPrefix(existing[".codex/config.toml"]!.trimmingCharacters(in: .newlines)))
        #expect(toml.contains("[mcp_servers.agentic-voice]\ncommand = \"\(executable)\"\nargs = [\"mcp\"]\ntool_timeout_sec = 360\n"))
        #expect(((try f.json(".codex/hooks.json")["hooks"] as? [String: Any])?["PermissionRequest"] as? [Any])?.count == 1)

        let vscode = try f.json("Library/Application Support/Code/User/mcp.json")
        #expect(((vscode["servers"] as? [String: Any])?["agentic-voice"] as? [String: Any])?["type"] as? String == "stdio")
        let opencode = try f.json(".config/opencode/opencode.json")
        #expect(equal(((opencode["mcp"] as? [String: Any])?["agentic-voice"] as? [String: Any])?["command"], [executable, "mcp"]))
        #expect(try f.home.read(".config/opencode/plugins/agentic-voice.js").contains("export * from \"file:///Applications/Agentic%20Voice.app/"))
    }

    @Test func reinstallingChangesNothingAndBacksUpTheOriginalOnce() throws {
        let f = try ClientsFixture()
        for (path, content) in existing { try f.home.write(path, content) }
        try f.installAll()
        let cursor = try f.home.read(".cursor/mcp.json")
        let codex = try f.home.read(".codex/config.toml")
        try f.installAll()

        #expect(try f.home.read(".cursor/mcp.json") == cursor)
        #expect(try f.home.read(".codex/config.toml") == codex)
        #expect(try f.home.read(".cursor/mcp.json.agentic-voice-backup") == existing[".cursor/mcp.json"])
        #expect(try f.home.read(".codex/config.toml.agentic-voice-backup") == existing[".codex/config.toml"])
        #expect(!f.home.exists(".codeium/windsurf/mcp_config.json.agentic-voice-backup"))
    }

    @Test func reinstallingFromAMovedAppUpdatesOutdatedEntries() throws {
        let f = try ClientsFixture()
        try Clients.install(f.context, "cursor")
        var moved = f.context
        moved.executable = "/Users/me/Agentic Voice.app/agentic-voice"
        #expect(try Clients.status(moved, "cursor").current == false)
        try Clients.install(moved, "cursor")
        #expect(try Clients.status(moved, "cursor").current)
    }

    @Test func replacesAHookFromANodeInstall() throws {
        let f = try ClientsFixture()
        try f.home.write(".claude/settings.json", #"{"hooks":{"Notification":[{"hooks":[{"type":"command","command":"AGENTIC_VOICE_NODE='/old/node' '/old/hooks/speak-notify.sh' input"}]}]}}"#)
        #expect(try Clients.status(f.context, "claude-code").current == false)
        try Clients.install(f.context, "claude-code")
        let notification = (try f.json(".claude/settings.json")["hooks"] as? [String: Any])?["Notification"] as? [[String: Any]]
        #expect(notification?.count == 1)
        #expect(((notification?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String) == hook)
    }

    @Test func uninstallingRemovesOnlyAgenticVoiceEntries() throws {
        let f = try ClientsFixture()
        for (path, content) in existing { try f.home.write(path, content) }
        try f.installAll()
        for id in Clients.ids { try Clients.uninstall(f.context, id) }

        for id in Clients.ids { #expect(try Clients.status(f.context, id).installed == false, "\(id)") }
        #expect(equal(try f.json(".cursor/mcp.json"), try JSONSerialization.jsonObject(with: Data(existing[".cursor/mcp.json"]!.utf8))))
        #expect(equal(try f.json(".claude/settings.json"), try JSONSerialization.jsonObject(with: Data(existing[".claude/settings.json"]!.utf8))))
        #expect(try f.home.read(".codex/config.toml") == existing[".codex/config.toml"])
        #expect(equal(try f.json(".claude.json")["mcpServers"], [String: Any]()))
        #expect(!f.home.exists(".config/opencode/plugins/agentic-voice.js"))
    }

    @Test(arguments: [
        "[mcp_servers.agentic-voice]", #"[mcp_servers."agentic-voice"] # mine"#, "[ mcp_servers . 'agentic-voice' ]",
        #"mcp_servers.agentic-voice.command = "node""#, #"mcp_servers = { agentic-voice = { command = "node" } }"#,
        #"[mcp_servers."agentic-voice"]"#, #"mcp_servers."agentic-voice".command = "node""#,
        "[mcp_servers]\nagentic-voice = { command = \"node\" }", "[mcp_servers]\n\"agentic-voice\".command = \"node\"",
    ])
    func refusesACodexTableDefinedOutsideTheManagedBlock(header: String) {
        let error = #expect(throws: AgenticVoiceError.self) {
            try ConfigEdit.upsertTOMLBlock("\(header)\ncommand = \"node\"\n", path: "config.toml", table: "mcp_servers.agentic-voice", body: "command = \"x\"\n")
        }
        #expect(error?.message.contains("already defines agentic-voice") == true)
    }

    @Test func acceptsAgenticVoiceKeysOutsideMCPServers() throws {
        let codex = [
            "[marketplaces.agentic-voice]", "source = \"/Users/me/agentic-voice\"", "",
            "[plugins.\"agentic-voice@agentic-voice\"]", "enabled = true", "",
            "[mcp_servers.other]", "command = \"other\"", "agentic-voice = \"not a server\"", "",
        ].joined(separator: "\n")
        let result = try ConfigEdit.upsertTOMLBlock(codex, path: "config.toml", table: "mcp_servers.agentic-voice", body: "command = \"x\"\n")
        #expect(result.contains("[mcp_servers.agentic-voice]\ncommand = \"x\"\n"))
    }

    @Test func refusesToReplaceAContainerThatIsNotAnObject() throws {
        let f = try ClientsFixture()
        let cursor = #"{"mcpServers":[{"name":"mine"}]}"#
        let claude = #"{"hooks":{"Notification":{"command":"say hi"}}}"#
        try f.home.write(".cursor/mcp.json", cursor)
        try f.home.write(".claude/settings.json", claude)
        #expect(throws: AgenticVoiceError.self) { try Clients.install(f.context, "cursor") }
        let hookError = #expect(throws: AgenticVoiceError.self) { try Clients.install(f.context, "claude-code") }
        #expect(hookError?.message.contains(#""Notification" is not an array"#) == true)
        #expect(try f.home.read(".cursor/mcp.json") == cursor)
        #expect(try f.home.read(".claude/settings.json") == claude)
        #expect(!f.home.exists(".claude.json"))
    }

    @Test func uninstallingTheOnlyHookLeavesNoEmptyHooksObject() throws {
        let f = try ClientsFixture()
        try f.home.write(".claude/settings.json", #"{"model":"opus"}"#)
        try Clients.install(f.context, "claude-code")
        try Clients.uninstall(f.context, "claude-code")
        #expect(equal(try f.json(".claude/settings.json"), ["model": "opus"]))
    }

    @Test func keepsOtherCommandsThatShareAHookGroup() throws {
        let f = try ClientsFixture()
        let theirs: [[String: Any]] = [["type": "command", "command": "/Users/me/bin/speak-notify.sh"], ["type": "command", "command": "say hi"]]
        let shared: [String: Any] = ["hooks": ["Notification": [["hooks": [["type": "command", "command": hook]] + theirs]]]]
        try f.home.write(".claude/settings.json", try ConfigEdit.render(shared))
        try Clients.install(f.context, "claude-code")
        var groups = (try f.json(".claude/settings.json")["hooks"] as? [String: Any])?["Notification"] as? [[String: Any]]
        #expect(equal(groups?.first?["hooks"], theirs))
        #expect(groups?.count == 2)

        try Clients.uninstall(f.context, "claude-code")
        groups = (try f.json(".claude/settings.json")["hooks"] as? [String: Any])?["Notification"] as? [[String: Any]]
        #expect(equal(groups, [["hooks": theirs]]))
    }

    @Test func keepsThePermissionsOfAReplacedFile() throws {
        let f = try ClientsFixture()
        try f.home.write(".codex/config.toml", "model = \"gpt\"\n", mode: 0o600)
        func mode() throws -> Int {
            (try FileManager.default.attributesOfItem(atPath: f.home.path(".codex/config.toml"))[.posixPermissions] as! NSNumber).intValue & 0o777
        }
        try Clients.install(f.context, "codex")
        #expect(try mode() == 0o600)
        try Clients.uninstall(f.context, "codex")
        #expect(try mode() == 0o600)
    }

    @Test func leavesAConfigWithCommentsUnchangedAndShowsTheEntry() throws {
        let f = try ClientsFixture()
        let jsonc = "{\n  // my servers\n  \"mcpServers\": {}\n}\n"
        try f.home.write(".cursor/mcp.json", jsonc)
        let error = #expect(throws: AgenticVoiceError.self) { try Clients.install(f.context, "cursor") }
        #expect(error?.message.contains("not plain JSON") == true)
        #expect(error?.message.contains("Add this manually") == true)
        #expect(error?.message.contains("\"agentic-voice\"") == true)
        #expect(try f.home.read(".cursor/mcp.json") == jsonc)
        let status = try Clients.status(f.context, "cursor")
        #expect(!status.installed)
        #expect(status.note?.contains("not plain JSON") == true)
    }

    @Test func warnsWhenTheClaudeCodePluginIsAlsoEnabled() throws {
        let f = try ClientsFixture()
        try f.home.write(".claude/settings.json", #"{"enabledPlugins":{"agentic-voice@agentic-voice":true}}"#)
        #expect(try Clients.status(f.context, "claude-code").note?.contains("plugin is also enabled") == true)
    }

    @Test func leavesAnOpencodePluginItDidNotWriteAlone() throws {
        let f = try ClientsFixture()
        try f.home.write(".config/opencode/plugins/agentic-voice.js", "export const mine = 1;\n")
        let error = #expect(throws: AgenticVoiceError.self) { try Clients.install(f.context, "opencode") }
        #expect(error?.message.contains("not written by Agentic Voice") == true)
        #expect(!f.home.exists(".config/opencode/opencode.json"), "no MCP entry from a refused install")
        #expect(try Clients.status(f.context, "opencode").installed == false)
        try Clients.uninstall(f.context, "opencode")
        #expect(try f.home.read(".config/opencode/plugins/agentic-voice.js") == "export const mine = 1;\n")
    }

    @Test func runReportsPerClientFailures() throws {
        let f = try ClientsFixture()
        try f.home.write(".cursor/mcp.json", "{ // comment\n}")
        let results = try Clients.run(.install, ["cursor", "windsurf"], context: f.context)
        #expect(results.map(\.id) == ["cursor", "windsurf"])
        #expect(results[0].error?.contains("not plain JSON") == true)
        #expect(results[1].error == nil && results[1].installed)
    }
}
