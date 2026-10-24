import AVFoundation
import FluidAudio
import Foundation

public enum ClonedVoiceStoreError: Error, LocalizedError {
    case invalidName(String)
    case invalidId(String)
    case exists(String)
    case unreadableAudio(String)
    case tooShort(Double)

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            return "'\(name)' can't name a voice; use letters or digits, like Max."
        case .invalidId(let id):
            return "'\(id)' is not a cloned voice id (expected something like clone_max)."
        case .exists(let id):
            return "A cloned voice '\(id)' already exists; delete it first or pick another name."
        case .unreadableAudio(let reason):
            return "Couldn't read the voice sample: \(reason)"
        case .tooShort(let seconds):
            return String(format: "The voice sample is %.1f s long; record at least %.0f s.", seconds, ClonedVoiceStore.minimumSeconds)
        }
    }
}

/// Clones voices from a short sample with FluidAudio's PocketTTS backend and keeps them as
/// `clone_<name>` voices, which the bridge speaks with PocketTTS instead of Kokoro.
public enum ClonedVoiceStore {
    public static let prefix = "clone_"
    static let minimumSeconds = 3.0
    /// PocketTTS's encoder reads this much of the sample and ignores the rest.
    public static let usedSeconds = PocketTtsVoiceCloner.maxDurationSeconds

    /// The user's own voices, so outside any cache that may be cleared.
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AgenticVoice/Voices", isDirectory: true)
    }

    static func file(for id: String) -> URL {
        directory.appendingPathComponent("\(id).bin")
    }

    /// Never matches a Kokoro id (`af_bella`), and keeps an id from naming a path outside the directory.
    public static func isValid(_ id: String) -> Bool {
        id.range(of: "^clone_[a-z0-9]+$", options: .regularExpression) != nil
    }

    /// "Max Müller" → `clone_maxmuller`.
    public static func id(forName name: String) throws -> String {
        let slug = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US_POSIX"))
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
            .prefix(32)
        guard !slug.isEmpty else { throw ClonedVoiceStoreError.invalidName(name) }
        return prefix + String(slug)
    }

    public static func isInstalled(_ id: String) -> Bool {
        isValid(id) && FileManager.default.fileExists(atPath: file(for: id).path)
    }

    /// Installed ids, sorted.
    public static func installed() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.filter { $0.hasSuffix(".bin") }.map { String($0.dropLast(4)) }.filter(isValid).sorted()
    }

    /// Clones the voice in `audio` (any format AVFoundation reads) and returns its id. The first
    /// clone downloads the PocketTTS model, which the bridge then reuses to speak.
    public static func clone(name: String, from audio: URL) async throws -> String {
        let id = try Self.id(forName: name)
        guard !isInstalled(id) else { throw ClonedVoiceStoreError.exists(id) }
        let seconds: Double
        do {
            let sample = try AVAudioFile(forReading: audio)
            seconds = Double(sample.length) / sample.processingFormat.sampleRate
        } catch {
            throw ClonedVoiceStoreError.unreadableAudio(error.localizedDescription)
        }
        guard seconds >= minimumSeconds else { throw ClonedVoiceStoreError.tooShort(seconds) }

        let manager = PocketTtsManager()
        try await manager.initialize()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await manager.cloneVoiceToFile(from: audio, to: file(for: id))
        return id
    }

    public static func remove(_ id: String) throws {
        guard isValid(id) else { throw ClonedVoiceStoreError.invalidId(id) }
        guard isInstalled(id) else { return }
        try FileManager.default.removeItem(at: file(for: id))
    }

    /// Speaks cloned voices. PocketTTS loads on the first request for one, so a bridge that only
    /// speaks Kokoro voices never pays for it.
    actor Speaker {
        private var manager: PocketTtsManager?

        func synthesize(text: String, voice id: String) async throws -> Data {
            let manager = try await loadedManager()
            let voiceData = try manager.loadClonedVoice(from: ClonedVoiceStore.file(for: id))
            return try await manager.synthesize(text: text, voiceData: voiceData)
        }

        private func loadedManager() async throws -> PocketTtsManager {
            if let manager { return manager }
            let manager = PocketTtsManager()
            try await manager.initialize()
            self.manager = manager
            return manager
        }
    }
}
