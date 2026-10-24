import Foundation

enum AppSettingsError: Error, LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let problem): return "Settings file \(AppSettings.url.path): \(problem). Fix or delete it."
        }
    }
}

/// The shared settings file; `AgenticVoiceKit`'s Config.swift reads it on every speak call.
struct AppSettings: Codable, Equatable {
    var voice: String?
    var speed: Double?

    init(voice: String? = nil, speed: Double? = nil) {
        self.voice = voice
        self.speed = speed
    }

    /// Like readSettings() in src/config.ts: a present key must hold a value (null is invalid),
    /// and the voice is trimmed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in [CodingKeys.voice, .speed] where container.contains(key) {
            if try container.decodeNil(forKey: key) {
                throw AppSettingsError.invalid("\"\(key.stringValue)\" must not be null")
            }
        }
        voice = try container.decodeIfPresent(String.self, forKey: .voice)?.trimmingCharacters(in: .whitespacesAndNewlines)
        speed = try container.decodeIfPresent(Double.self, forKey: .speed)
    }

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AgenticVoice/config.json")
    }

    /// Applies Config.swift's rules for the two keys the app edits, so it never shows or writes
    /// back a value the speak path would reject.
    static func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppSettings() }
        let settings: AppSettings
        do {
            settings = try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: url))
        } catch let error as AppSettingsError {
            throw error
        } catch {
            throw AppSettingsError.invalid("is not valid JSON with a string voice and numeric speed")
        }
        if let voice = settings.voice, voice.isEmpty {
            throw AppSettingsError.invalid("\"voice\" must be a non-empty string")
        }
        if let speed = settings.speed, !(speed.isFinite && speed > 0) {
            throw AppSettingsError.invalid("\"speed\" must be a positive number")
        }
        return settings
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.url, options: .atomic)
    }
}
