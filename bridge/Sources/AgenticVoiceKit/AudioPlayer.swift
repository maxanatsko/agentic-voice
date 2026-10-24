import Foundation

/// Plays WAV audio through a command (`afplay` by default) and owns the cross-process speaking lock.
public struct AudioPlayer: Sendable {
    let command: String
    let lockPort: UInt16

    public init(command: String = "afplay", lockPort: UInt16 = PortLock.speaking) {
        self.command = command
        self.lockPort = lockPort
    }

    /// Claims the speaker across processes. Returns nil if another session is speaking.
    public func claim() throws -> PortLock? {
        do {
            return try PortLock.acquire(lockPort)
        } catch {
            throw AgenticVoiceError("Cannot claim the speaker on 127.0.0.1:\(lockPort): \(error.localizedDescription)")
        }
    }

    public func play(_ wav: Data) async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("agentic-voice-\(UUID().uuidString).wav")
        try wav.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let process = Process()
        // Through env, so a bare command name is looked up on PATH.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command, file.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.standardError
        let status: Int32
        do {
            status = try await process.runToExit()
        } catch {
            throw AgenticVoiceError("Audio playback failed using '\(command)': \(error.localizedDescription)")
        }
        guard status == 0 else {
            throw AgenticVoiceError("Audio playback failed using '\(command)' (exit status \(status))")
        }
    }
}

extension Process {
    /// Runs the process and waits for it without blocking a thread.
    func runToExit() async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try run()
            } catch {
                terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
