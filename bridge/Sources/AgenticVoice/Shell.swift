import Foundation

/// Runs a program to completion and captures its output. Callers keep it off the main thread.
enum Shell {
    /// Written by one reader thread, read only after it finishes (the DispatchGroup orders them).
    private final class Collected: @unchecked Sendable {
        var data = Data()
    }

    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil, timeout: TimeInterval = 60) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        // Drain stderr concurrently, so a chatty child can't block on a full pipe.
        let errorData = Collected()
        let errorRead = DispatchGroup()
        errorRead.enter()
        DispatchQueue.global().async {
            errorData.data = stderr.fileHandleForReading.readDataToEndOfFile()
            errorRead.leave()
        }
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        errorRead.wait()
        process.waitUntilExit()
        timer.cancel()

        return Result(
            status: process.terminationStatus,
            stdout: String(decoding: outputData, as: UTF8.self),
            stderr: String(decoding: errorData.data, as: UTF8.self)
        )
    }
}
