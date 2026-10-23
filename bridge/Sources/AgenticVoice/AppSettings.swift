import Foundation

/// The shared settings file; the Node side's src/config.ts reads it on every speak call.
struct AppSettings: Codable, Equatable {
    var voice: String?
    var speed: Double?

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AgenticVoice/config.json")
    }

    static func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppSettings() }
        return try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: url))
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.url, options: .atomic)
    }
}
