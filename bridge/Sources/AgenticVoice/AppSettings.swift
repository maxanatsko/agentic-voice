import Foundation

enum AppSettingsError: Error, LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let problem): return "Settings file \(AppSettings.url.path): \(problem). Fix or delete it."
        }
    }
}

/// The shared settings file; the Node side's src/config.ts reads it on every speak call.
struct AppSettings: Codable, Equatable {
    var voice: String?
    var speed: Double?

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AgenticVoice/config.json")
    }

    /// Applies src/config.ts's rules for the two keys the app edits, so it never shows or writes
    /// back a value the Node side would reject.
    static func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppSettings() }
        let settings: AppSettings
        do {
            settings = try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: url))
        } catch {
            throw AppSettingsError.invalid("is not valid JSON with a string voice and numeric speed")
        }
        if let voice = settings.voice, voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
