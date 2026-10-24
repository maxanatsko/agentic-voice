@testable import AgenticVoiceKit
import Foundation
import Synchronization
import Testing

private let ready = #"{"status":"ready"}"#

/// A fake TTSBridge: a script that records its PID. In `.serve` mode the test serves health on
/// the bridge's port while that process lives, as the real bridge would once its model loads.
final class BridgeFixture: Sendable {
    enum Mode { case serve(after: Duration = .zero), exit, hang, stubborn }

    let directory: TemporaryDirectory
    let executable: String
    let bridge: BridgeProcess
    private let serving: Task<Void, Error>?

    init(port: UInt16, lockPort: UInt16, mode: Mode, startupTimeout: Duration = .seconds(2)) throws {
        let directory = try TemporaryDirectory()
        let pidFile = directory.path("pid")
        let body: String
        switch mode {
        case .serve, .hang: body = "exec sleep 600"
        case .exit: body = "exit 23"
        case .stubborn: body = "trap '' TERM\nwhile true; do sleep 0.05; done"
        }
        executable = try directory.write("TTSBridge", "#!/bin/bash\necho $$ > '\(pidFile)'\n\(body)\n", mode: 0o755)
        var options = BridgeProcess.Options(executable: URL(fileURLWithPath: executable))
        options.startupTimeout = startupTimeout
        options.pollInterval = .milliseconds(20)
        options.shutdownTimeout = .milliseconds(100)
        options.startupLockPort = lockPort
        bridge = BridgeProcess(url: "http://127.0.0.1:\(port)", options: options)
        self.directory = directory
        if case .serve(let delay) = mode {
            serving = Task {
                while !directory.exists("pid") { try await Task.sleep(for: .milliseconds(10)) }
                let pid = Int32(try directory.read("pid").trimmingCharacters(in: .whitespacesAndNewlines))!
                try await Task.sleep(for: delay)
                let server = try await TestHTTPServer(port: port) { $0 == "/v1/audio/health" ? (200, ready) : (200, "welcome") }
                defer { server.close() }
                while alive(pid) { try await Task.sleep(for: .milliseconds(10)) }
            }
        } else {
            serving = nil
        }
    }

    var spawned: Bool { directory.exists("pid") }

    func pid() async throws -> Int32 {
        try await eventually { (try? directory.read("pid"))?.hasSuffix("\n") == true }
        return Int32(try directory.read("pid").trimmingCharacters(in: .whitespacesAndNewlines))!
    }

    deinit { serving?.cancel() }
}

private func message(_ error: (any Error)?) -> String {
    error?.localizedDescription ?? ""
}

@Suite(.serialized)
struct BridgeProcessTests {
    @Test func reusesABackendThroughHealthWithoutSpawning() async throws {
        let server = try await TestHTTPServer { $0 == "/v1/audio/health" ? (200, ready) : (200, "different backend") }
        defer { server.close() }
        let bridge = BridgeProcess(url: server.url, options: .init(executable: URL(fileURLWithPath: "/missing/TTSBridge")))
        try await bridge.start()
        await bridge.stop()
    }

    @Test func waitsForABackendReportingInitialization() async throws {
        let requests = Counter()
        let server = try await TestHTTPServer { _ in
            requests.increment() == 1 ? (503, #"{"status":"initializing"}"#) : (200, ready)
        }
        defer { server.close() }
        var options = BridgeProcess.Options(executable: URL(fileURLWithPath: "/missing/TTSBridge"))
        options.pollInterval = .milliseconds(20)
        let bridge = BridgeProcess(url: server.url, options: options)
        try await bridge.start()
        #expect(requests.value == 2)
        await bridge.stop()
    }

    @Test func startsAChildAndStopsOnlyThatChild() async throws {
        let port = freePort()
        let lockPort = freePort()
        let owned = try BridgeFixture(port: port, lockPort: lockPort, mode: .serve())
        try await owned.bridge.start()
        let pid = try await owned.pid()
        #expect(alive(pid))

        let borrower = BridgeProcess(url: "http://127.0.0.1:\(port)", options: .init(executable: URL(fileURLWithPath: "/missing/TTSBridge")))
        try await borrower.start()
        await borrower.stop()
        #expect(alive(pid))

        async let first: Void = owned.bridge.stop()
        async let second: Void = owned.bridge.stop()
        _ = await (first, second)
        #expect(!alive(pid))

        for _ in 0..<200 where try await TTSClient.checkReadiness("http://127.0.0.1:\(port)") != .unavailable {
            try await Task.sleep(for: .milliseconds(10))
        }
        let replacement = try BridgeFixture(port: port, lockPort: lockPort, mode: .serve())
        try await replacement.bridge.start()
        await replacement.bridge.stop()
    }

    @Test func missingExecutableAndOccupiedEndpointHaveActionableErrors() async throws {
        var options = BridgeProcess.Options(executable: URL(fileURLWithPath: "/missing/TTSBridge"))
        options.startupLockPort = freePort()
        let missing = BridgeProcess(url: "http://127.0.0.1:\(freePort())", options: options)
        let missingError = await #expect(throws: AgenticVoiceError.self) { try await missing.start() }
        #expect(message(missingError).contains("Cannot execute TTSBridge at /missing/TTSBridge"))
        await missing.stop()

        let server = try await TestHTTPServer { _ in (200, "different service") }
        defer { server.close() }
        let occupied = BridgeProcess(url: server.url, options: options)
        let occupiedError = await #expect(throws: AgenticVoiceError.self) { try await occupied.start() }
        #expect(message(occupiedError).contains("does not implement GET /v1/audio/health"))
    }

    @Test func prematureExitAndTimeoutExplainWhatToDo() async throws {
        let failed = try BridgeFixture(port: freePort(), lockPort: freePort(), mode: .exit)
        let exitError = await #expect(throws: AgenticVoiceError.self) { try await failed.bridge.start() }
        #expect(message(exitError).contains("failed before readiness"))
        #expect(message(exitError).contains("exit code 23"))

        let hung = try BridgeFixture(port: freePort(), lockPort: freePort(), mode: .hang, startupTimeout: .milliseconds(300))
        let timeoutError = await #expect(throws: AgenticVoiceError.self) { try await hung.bridge.start() }
        #expect(message(timeoutError).contains("Timed out waiting for TTSBridge"))
        let pid = try await hung.pid()
        await hung.bridge.stop()
        #expect(!alive(pid))
    }

    @Test func reportsSpawnErrorsAndForceStopsAnUnresponsiveChild() async throws {
        let invalid = try BridgeFixture(port: freePort(), lockPort: freePort(), mode: .hang)
        try invalid.directory.write("TTSBridge", "#!/missing/interpreter\n", mode: 0o755)
        let spawnError = await #expect(throws: AgenticVoiceError.self) { try await invalid.bridge.start() }
        #expect(message(spawnError).contains("failed before readiness"))

        let stubborn = try BridgeFixture(port: freePort(), lockPort: freePort(), mode: .stubborn)
        let starting = Task { try await stubborn.bridge.start() }
        let pid = try await stubborn.pid()
        await stubborn.bridge.stop()
        let abortError = await #expect(throws: AgenticVoiceError.self) { try await starting.value }
        #expect(message(abortError).contains("aborted"))
        #expect(!alive(pid))
    }

    @Test func coldStartupIsSerializedBeforeSpawning() async throws {
        let port = freePort()
        let lockPort = freePort()
        let first = try BridgeFixture(port: port, lockPort: lockPort, mode: .serve(after: .milliseconds(300)))
        let second = try BridgeFixture(port: port, lockPort: lockPort, mode: .serve())
        let starting = Task { try await first.bridge.start() }
        let firstPid = try await first.pid()
        #expect(try await TTSClient.checkReadiness("http://127.0.0.1:\(port)") == .unavailable)
        try await second.bridge.start()
        try await starting.value
        #expect(!second.spawned)
        await second.bridge.stop()
        #expect(try await TTSClient.checkReadiness("http://127.0.0.1:\(port)") == .ready)
        #expect(alive(firstPid))
        await first.bridge.stop()
    }

    @Test func stoppingAWaiterLeavesTheOwnerRunning() async throws {
        let port = freePort()
        let lockPort = freePort()
        let first = try BridgeFixture(port: port, lockPort: lockPort, mode: .hang)
        let second = try BridgeFixture(port: port, lockPort: lockPort, mode: .serve())
        let ownerStarting = Task { try await first.bridge.start() }
        let pid = try await first.pid()
        let waiting = Task { try await second.bridge.start() }
        try await Task.sleep(for: .milliseconds(80))
        #expect(!second.spawned)
        await second.bridge.stop()
        await #expect(throws: AgenticVoiceError.self) { try await waiting.value }
        #expect(alive(pid))
        await first.bridge.stop()
        await #expect(throws: AgenticVoiceError.self) { try await ownerStarting.value }
    }

    @Test func anOccupiedCoordinationPortTimesOutWithoutSpawning() async throws {
        let lockServer = try await TestHTTPServer { _ in (200, "") }
        defer { lockServer.close() }
        let fixture = try BridgeFixture(port: freePort(), lockPort: lockServer.port, mode: .hang, startupTimeout: .milliseconds(150))
        let error = await #expect(throws: AgenticVoiceError.self) { try await fixture.bridge.start() }
        #expect(message(error).contains("coordination port is available"))
        #expect(!fixture.spawned)
    }
}

final class Counter: Sendable {
    private let count = Mutex(0)
    var value: Int { count.withLock { $0 } }
    func increment() -> Int { count.withLock { $0 += 1; return $0 } }
}
