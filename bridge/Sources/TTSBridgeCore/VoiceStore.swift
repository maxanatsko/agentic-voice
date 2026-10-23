import Foundation

public enum VoiceStoreError: Error, LocalizedError {
    case invalidId(String)
    case downloadFailed(String, Int)
    case unzipFailed(String, Int32)
    case unexpectedSize(String, Int)

    public var errorDescription: String? {
        switch self {
        case .invalidId(let id):
            return "'\(id)' is not a Kokoro voice id (expected something like af_bella)."
        case .downloadFailed(let id, let status):
            return "Downloading voice '\(id)' failed with HTTP \(status); the voice id probably doesn't exist."
        case .unzipFailed(let id, let status):
            return "Extracting voice '\(id)' failed (unzip exit code \(status))."
        case .unexpectedSize(let id, let size):
            return "Voice '\(id)' has \(size) bytes of data, expected \(VoiceStore.packSize); not installed."
        }
    }
}

/// Installs Kokoro voices into the cache FluidAudio's Kokoro-ANE backend reads them from.
public enum VoiceStore {
    /// A flat [510, 256] float32 voice pack.
    static let packSize = 510 * 256 * 4

    /// FluidAudio's convention, not something this package controls.
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/fluidaudio/Models/kokoro-82m-coreml/ANE", isDirectory: true)
    }

    static func file(for id: String) -> URL {
        directory.appendingPathComponent("\(id).bin")
    }

    public static func isInstalled(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: file(for: id).path)
    }

    /// Downloads the official Kokoro `.pt` voice and extracts its tensor. No Python or torch is
    /// needed: a `.pt` voice is an uncompressed zip whose `<voice>/data/0` entry already holds the
    /// little-endian float32 bytes FluidAudio reads.
    public static func install(_ id: String) async throws {
        guard id.range(of: "^[a-z]{2}_[a-z]+$", options: .regularExpression) != nil else {
            throw VoiceStoreError.invalidId(id)
        }
        if isInstalled(id) { return }

        let remote = URL(string: "https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/voices/\(id).pt")!
        let (archive, response) = try await URLSession.shared.download(from: remote)
        defer { try? FileManager.default.removeItem(at: archive) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw VoiceStoreError.downloadFailed(id, status) }

        let pack = try unzipEntry("\(id)/data/0", from: archive, voice: id)
        guard pack.count == packSize else { throw VoiceStoreError.unexpectedSize(id, pack.count) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try pack.write(to: file(for: id), options: .atomic)
    }

    public static func remove(_ id: String) throws {
        guard isInstalled(id) else { return }
        try FileManager.default.removeItem(at: file(for: id))
    }

    private static func unzipEntry(_ entry: String, from archive: URL, voice: String) throws -> Data {
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-p", archive.path, entry]
        let output = Pipe()
        unzip.standardOutput = output
        unzip.standardError = FileHandle.nullDevice
        try unzip.run()
        // Read before waiting, so a full pipe can't block unzip.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            throw VoiceStoreError.unzipFailed(voice, unzip.terminationStatus)
        }
        return data
    }
}
