import Foundation

/// Makes the bundled bridge ready: reuses a healthy one, otherwise takes the startup lock and
/// launches TTSBridge as a child. Owns only the child it launches; an already-running bridge is
/// never signalled.
public actor BridgeProcess {
    public struct Options: Sendable {
        public var executable: URL
        public var startupTimeout: Duration = .seconds(300)
        public var pollInterval: Duration = .milliseconds(500)
        public var shutdownTimeout: Duration = .seconds(5)
        public var startupLockPort: UInt16 = PortLock.bridgeStartup

        public init(executable: URL) {
            self.executable = executable
        }
    }

    private let url: String
    private let options: Options
    private var child: Process?
    private var failure: String?
    private var startupLock: PortLock?
    private var stopped = false
    private var stopping: Task<Void, Never>?

    public init(url: String, options: Options) {
        self.url = url
        self.options = options
    }

    public func start() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + options.startupTimeout
        let executable = options.executable.path
        while clock.now < deadline {
            try checkNotStopped()
            let health = try await TTSClient.checkReadiness(url)
            try checkNotStopped()
            if health == .ready {
                if child == nil { releaseStartupLock() }
                printError("agentic-voice: \(child == nil ? "reusing bridge" : "bridge ready") at \(url)")
                return
            }
            if health == .occupied {
                throw AgenticVoiceError("TTS endpoint \(url) does not implement GET /v1/audio/health readiness. Free port 9000 or provide the documented health endpoint; use a remote/custom TTS_URL for an externally managed backend.")
            }
            if let failure {
                throw AgenticVoiceError("TTSBridge \(executable) failed before readiness at \(url): \(failure). Check the bridge diagnostics above; run TTSBridge directly to diagnose model initialization or port conflicts.")
            }
            if health == .unavailable && child == nil {
                if startupLock == nil {
                    if try acquireStartupLock() { continue }  // Recheck readiness after gaining ownership.
                } else {
                    try spawn()
                }
            }
            try await Task.sleep(for: options.pollInterval)
        }
        throw AgenticVoiceError("Timed out waiting for TTSBridge \(executable) at \(url) or startup coordination on 127.0.0.1:\(options.startupLockPort). Another MCP instance may be initializing; ensure the coordination port is available. First-use model downloads may need more time; run TTSBridge directly to initialize the cache and inspect its diagnostics, then restart MCP.")
    }

    /// Stops the child this instance launched, if any, and cancels a pending start.
    public func stop() async {
        if stopping == nil { stopping = Task { await stopChild() } }
        await stopping?.value
    }

    private func checkNotStopped() throws {
        try Task.checkCancellation()
        if stopped { throw AgenticVoiceError("TTSBridge startup was aborted because agentic-voice is shutting down.") }
    }

    private func acquireStartupLock() throws -> Bool {
        do {
            startupLock = try PortLock.acquire(options.startupLockPort)
        } catch {
            throw AgenticVoiceError("Cannot coordinate TTSBridge startup: \(error.localizedDescription)")
        }
        return startupLock != nil
    }

    private func releaseStartupLock() {
        startupLock?.release()
        startupLock = nil
    }

    private func spawn() throws {
        let executable = options.executable
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw AgenticVoiceError("Cannot execute TTSBridge at \(executable.path). Build it with swift build -c release --package-path bridge before starting MCP.")
        }
        printError("agentic-voice: starting \(executable.path); waiting for \(url) (first use may download model assets; later starts use the cache)")
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        process.standardInput = FileHandle.nullDevice
        // Bridge output is diagnostics; stdout belongs to MCP.
        process.standardOutput = FileHandle.standardError
        process.standardError = FileHandle.standardError
        process.terminationHandler = { [weak self] process in
            let reason = process.terminationReason == .uncaughtSignal
                ? "killed by signal \(process.terminationStatus)"
                : "exit code \(process.terminationStatus)"
            Task { await self?.childExited(reason) }
        }
        // Store ownership before running, so a concurrent stop always sees this child.
        child = process
        do {
            try process.run()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func childExited(_ reason: String) {
        failure = failure ?? reason
        releaseStartupLock()
    }

    private func stopChild() async {
        stopped = true
        defer { releaseStartupLock() }
        guard let child, child.isRunning else { return }
        child.terminate()
        let clock = ContinuousClock()
        let deadline = clock.now + options.shutdownTimeout
        while child.isRunning && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        while child.isRunning {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// Diagnostics go to stderr: stdout is reserved for MCP protocol traffic.
public func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
