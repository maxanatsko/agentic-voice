import Foundation

/// Pure text edits for client config files. Callers own reading, backups and writing.
///
/// JSON is rewritten through Foundation, which doesn't keep key order: an edited file comes back
/// pretty-printed with sorted keys, its contents otherwise unchanged.
enum ConfigEdit {
    typealias JSONObject = [String: Any]

    static let tomlBegin = "# >>> agentic-voice (managed by Agentic Voice; edits inside this block are replaced)"
    static let tomlEnd = "# <<< agentic-voice"

    // MARK: JSON

    static func parseObject(_ text: String, path: String, snippet: Any) throws -> JSONObject {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        } catch {
            let entry = (try? render(snippet).trimmingCharacters(in: .newlines)) ?? ""
            throw AgenticVoiceError("\(path) is not plain JSON (it may contain comments), so it was left unchanged. Add this manually:\n\(entry)")
        }
        guard let object = parsed as? JSONObject else {
            throw AgenticVoiceError("\(path) does not contain a JSON object, so it was left unchanged.")
        }
        return object
    }

    /// An existing value under `key` must be an object; replacing anything else would discard it.
    private static func objectAt(_ root: JSONObject, _ key: String, path: String) throws -> JSONObject {
        guard let value = root[key] else { return [:] }
        guard let object = value as? JSONObject else {
            throw AgenticVoiceError("\(path): \"\(key)\" is not an object, so the file was left unchanged. Fix it, then install again.")
        }
        return object
    }

    static func render(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    static func jsonEqual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return (a as AnyObject).isEqual(b)
        default: return false
        }
    }

    static func readJSONEntry(_ text: String, path: String, container: String, name: String) throws -> Any? {
        let root = try parseObject(text, path: path, snippet: [:] as JSONObject)
        return (root[container] as? JSONObject)?[name]
    }

    static func upsertJSONEntry(_ text: String, path: String, container: String, name: String, entry: Any) throws -> String {
        var root = try parseObject(text, path: path, snippet: [container: [name: entry]])
        var servers = try objectAt(root, container, path: path)
        servers[name] = entry
        root[container] = servers
        return try render(root)
    }

    static func removeJSONEntry(_ text: String, path: String, container: String, name: String) throws -> String {
        var root = try parseObject(text, path: path, snippet: [:] as JSONObject)
        guard var servers = root[container] as? JSONObject, servers[name] != nil else { return text }
        servers[name] = nil
        root[container] = servers
        return try render(root)
    }

    // MARK: Hooks

    /// Marks the hook commands the installer writes.
    static let hookMarker = "# managed by agentic-voice"

    /// Ours is a hook the installer wrote: marked, or, from the earlier Node-based installer,
    /// `AGENTIC_VOICE_NODE=… …/hooks/speak-notify.sh …`, so an update replaces it.
    private static func isOurHook(_ hook: Any) -> Bool {
        guard let command = (hook as? JSONObject)?["command"] as? String else { return false }
        return command.hasSuffix(hookMarker) ||
            (command.hasPrefix("AGENTIC_VOICE_NODE=") && command.contains("/hooks/speak-notify.sh"))
    }

    private static func hookGroups(_ root: JSONObject, _ event: String) -> [Any] {
        ((root["hooks"] as? JSONObject)?[event] as? [Any]) ?? []
    }

    /// Drops our hooks from every group, and any group left empty, keeping other commands.
    private static func withoutOurHooks(_ groups: [Any]) -> [Any] {
        groups.compactMap { group in
            guard var object = group as? JSONObject, let hooks = object["hooks"] as? [Any], hooks.contains(where: isOurHook) else {
                return group
            }
            let kept = hooks.filter { !isOurHook($0) }
            if kept.isEmpty { return nil }
            object["hooks"] = kept
            return object
        }
    }

    static func readHookCommand(_ text: String, path: String, event: String) throws -> String? {
        for group in hookGroups(try parseObject(text, path: path, snippet: [:] as JSONObject), event) {
            if let hooks = (group as? JSONObject)?["hooks"] as? [Any], let hook = hooks.first(where: isOurHook) {
                return (hook as? JSONObject)?["command"] as? String
            }
        }
        return nil
    }

    static func upsertHook(_ text: String, path: String, event: String, command: String) throws -> String {
        let group: JSONObject = ["hooks": [["type": "command", "command": command, "timeout": 10] as JSONObject]]
        var root = try parseObject(text, path: path, snippet: ["hooks": [event: [group]]])
        var hooks = try objectAt(root, "hooks", path: path)
        if let existing = hooks[event], !(existing is [Any]) {
            throw AgenticVoiceError("\(path): hooks \"\(event)\" is not an array, so the file was left unchanged. Fix it, then install again.")
        }
        hooks[event] = withoutOurHooks(hookGroups(root, event)) + [group]
        root["hooks"] = hooks
        return try render(root)
    }

    static func removeHook(_ text: String, path: String, event: String) throws -> String {
        var root = try parseObject(text, path: path, snippet: [:] as JSONObject)
        let groups = hookGroups(root, event)
        let kept = withoutOurHooks(groups)
        if jsonEqual(kept, groups) { return text }
        var hooks = (root["hooks"] as? JSONObject) ?? [:]
        hooks[event] = kept.isEmpty ? nil : kept
        root["hooks"] = hooks.isEmpty ? nil : hooks
        return try render(root)
    }

    // MARK: TOML

    /// A dotted TOML key without spacing, quotes or escapes: ` a . "bc" ` → ["a", "bc"].
    private static func keyPath(_ key: some StringProtocol) -> [String] {
        key.split(separator: ".", omittingEmptySubsequences: false).map { part in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
                // JSON escapes cover TOML basic-string escapes in practice.
                if let decoded = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: [.fragmentsAllowed]) as? String {
                    return decoded
                }
                return String(trimmed.dropFirst().dropLast())
            }
            if trimmed.count >= 2, trimmed.hasPrefix("'"), trimmed.hasSuffix("'") {
                return String(trimmed.dropFirst().dropLast())
            }
            return trimmed
        }
    }

    /// True when the text defines the table as a header, dotted key or inline-table key, however quoted.
    /// Tracks the current table so a same-named key elsewhere (such as [marketplaces.agentic-voice]) is not a match.
    private static func definesTOMLTable(_ text: String, table: String) -> Bool {
        let target = keyPath(table)
        let last = NSRegularExpression.escapedPattern(for: target.last ?? "")
        let inlineKey = try! NSRegularExpression(pattern: #"[{,]\s*["']?"# + last + #"["']?\s*[.=]"#)
        var current: [String] = []
        for line in text.components(separatedBy: "\n") {
            let code = (line.firstIndex(of: "#").map { String(line[..<$0]) } ?? line).trimmingCharacters(in: .whitespaces)
            let path: [String]
            var value = ""
            if let header = code.wholeMatch(of: /\[\[?([^\[\]]+)\]\]?/) {
                current = keyPath(header.1)
                path = current
            } else if let assignment = code.wholeMatch(of: /([^=]+)=(.*)/) {
                path = current + keyPath(assignment.1)
                value = String(assignment.2)
            } else {
                continue
            }
            if path.count >= target.count && Array(path.prefix(target.count)) == target { return true }
            // An inline table one level up, such as mcp_servers = { agentic-voice = { … } }.
            if path.count == target.count - 1 && Array(target.prefix(path.count)) == path &&
                inlineKey.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil {
                return true
            }
        }
        return false
    }

    private static func tomlBlockRange(_ text: String) throws -> Range<String.Index>? {
        guard let begin = text.range(of: tomlBegin) else { return nil }
        guard let end = text.range(of: tomlEnd, range: begin.lowerBound..<text.endIndex) else {
            throw AgenticVoiceError("Found the start of the agentic-voice block without its end marker '\(tomlEnd)'; fix the file manually.")
        }
        return begin.lowerBound..<end.upperBound
    }

    static func readTOMLBlock(_ text: String) throws -> String? {
        try tomlBlockRange(text).map { String(text[$0]) }
    }

    static func tomlBlock(table: String, body: String) -> String {
        "\(tomlBegin)\n[\(table)]\n\(body)\(tomlEnd)"
    }

    /// Appends a managed block; a table at the end of a TOML file is always valid.
    static func upsertTOMLBlock(_ text: String, path: String, table: String, body: String) throws -> String {
        let stripped = try removeTOMLBlock(text)
        if definesTOMLTable(stripped, table: table) {
            let key = table.split(separator: ".").last.map(String.init) ?? table
            throw AgenticVoiceError("\(path) already defines \(key) outside the agentic-voice block (for example [\(table)]); remove it, then install again.")
        }
        let base = stripped.trimmingTrailingWhitespace()
        return "\(base.isEmpty ? "" : "\(base)\n\n")\(tomlBlock(table: table, body: body))\n"
    }

    static func removeTOMLBlock(_ text: String) throws -> String {
        guard let range = try tomlBlockRange(text) else { return text }
        let kept = [
            String(text[..<range.lowerBound]).trimmingTrailingWhitespace(),
            String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines),
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
        return kept.isEmpty ? "" : "\(kept)\n"
    }

    /// JSON string escapes are valid TOML basic-string escapes.
    static func jsonString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        String(reversed().drop(while: \.isWhitespace).reversed())
    }
}
