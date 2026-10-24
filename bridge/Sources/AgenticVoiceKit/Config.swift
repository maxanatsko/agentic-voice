import Foundation

public struct AppConfig: Equatable, Sendable {
    public var ttsURL: String
    public var voice: String
    public var language: String
    public var speed: Double
    public var maxChars: Int
    public var playbackCommand: String?
}

/// Voice and speed from the shared settings file, which the Agentic Voice app writes.
public struct Settings: Equatable, Sendable {
    public var voice: String?
    public var speed: Double?

    public init(voice: String? = nil, speed: Double? = nil) {
        self.voice = voice
        self.speed = speed
    }
}

/// Configuration: environment variables, then the settings file, then defaults.
public enum Config {
    /// Written by the Agentic Voice macOS app; environment variables override it.
    public static let settingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/AgenticVoice/config.json")

    public static let bundledTTSURL = "http://127.0.0.1:9000"

    /// True for the loopback endpoint on port 9000 that the bundled bridge serves.
    public static func isBundledTTSURL(_ value: String) -> Bool {
        guard let url = URLComponents(string: value) else { return false }
        return url.scheme?.lowercased() == "http" &&
            ["127.0.0.1", "localhost", "::1", "[::1]"].contains(url.host?.lowercased() ?? "") &&
            url.port == 9000 && ["", "/"].contains(url.path) && url.query == nil && url.fragment == nil &&
            url.user == nil && url.password == nil
    }

    public static func readSettings(at url: URL = settingsURL) throws -> Settings {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return Settings()
        }

        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw AgenticVoiceError("Settings file \(url.path) is not valid JSON. Fix or delete it.")
        }
        guard let object = parsed as? [String: Any] else {
            throw AgenticVoiceError("Settings file \(url.path) must contain a JSON object.")
        }

        var settings = Settings()
        if let voice = object["voice"] {
            guard let voice = voice as? String, !voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AgenticVoiceError("Settings file \(url.path): \"voice\" must be a non-empty string.")
            }
            settings.voice = voice.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let speed = object["speed"] {
            guard let number = speed as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue > 0 else {
                throw AgenticVoiceError("Settings file \(url.path): \"speed\" must be a positive number.")
            }
            settings.speed = number.doubleValue
        }
        return settings
    }

    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        settings: Settings? = nil
    ) throws -> AppConfig {
        let settings = try settings ?? readSettings()
        func value(_ key: String) -> String? {
            let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        return AppConfig(
            ttsURL: value("TTS_URL") ?? bundledTTSURL,
            voice: value("TTS_VOICE") ?? settings.voice ?? "am_michael",
            language: value("TTS_LANGUAGE") ?? "en-US",
            speed: try positiveNumber(environment["VOICE_SPEED"]) ?? settings.speed ?? 1.0,
            maxChars: try positiveInteger(environment["VOICE_MAX_CHARS"]) ?? 1200,
            playbackCommand: value("VOICE_PLAYBACK_COMMAND")
        )
    }

    /// Parses `.env` text: `KEY=VALUE` lines and `#` comments, including a comment after an
    /// unquoted value or after a quoted value's closing quote, as Node's loader does.
    public static func parseDotEnv(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            var line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }
            guard !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let raw = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            let value: String
            if let quote = raw.first, quote == "\"" || quote == "'",
               let close = raw.dropFirst().firstIndex(of: quote) {
                value = String(raw[raw.index(after: raw.startIndex)..<close])
            } else {
                value = String(raw.prefix { $0 != "#" }).trimmingCharacters(in: .whitespaces)
            }
            if !key.isEmpty { values[key] = value }
        }
        return values
    }

    private static func positiveInteger(_ value: String?) throws -> Int? {
        guard let value else { return nil }
        guard let parsed = Int(value.trimmingCharacters(in: .whitespaces)), parsed > 0 else {
            throw AgenticVoiceError("Expected a positive integer, received: \(value)")
        }
        return parsed
    }

    private static func positiveNumber(_ value: String?) throws -> Double? {
        guard let value else { return nil }
        guard let parsed = Double(value.trimmingCharacters(in: .whitespaces)), parsed.isFinite, parsed > 0 else {
            throw AgenticVoiceError("Expected a positive number, received: \(value)")
        }
        return parsed
    }
}
