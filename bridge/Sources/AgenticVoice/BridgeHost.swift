import AgenticVoiceKit
import AppKit
import Foundation
import TTSBridgeCore
import Vapor

/// Serves the bridge on 127.0.0.1:9000 from inside the app, following the same protocol as
/// AgenticVoiceKit's BridgeProcess: reuse a healthy bridge, otherwise take the startup lock,
/// prepare the model and serve, holding the lock while serving.
@MainActor
final class BridgeHost: ObservableObject {
    enum State: Equatable {
        case starting
        case waiting
        case preparing(String, fraction: Double?)
        case running
        case external
        case failed(String)

        var summary: String {
            switch self {
            case .starting: return "Starting…"
            case .waiting: return "Waiting for another process to start the voice engine…"
            case .preparing(let step, let fraction):
                return fraction.map { "\(step) \(Int($0 * 100))%" } ?? step
            case .running: return "Voice engine running"
            case .external: return "Using a voice engine started elsewhere"
            case .failed(let message): return "Voice engine failed: \(message)"
            }
        }
    }

    @Published private(set) var state: State = .starting
    private var app: Application?
    private var startupLock: PortLock?
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        state = .starting
        task = Task { await run() }
    }

    /// Stops serving. MCP servers that were using this bridge can't speak until they restart.
    func stop() async {
        task?.cancel()
        task = nil
        let app = self.app
        self.app = nil
        try? await app?.asyncShutdown()
        startupLock?.release()
        startupLock = nil
    }

    private func run() async {
        while !Task.isCancelled {
            if await Self.isHealthy() {
                // Another process serves the bridge; take over if it goes away.
                state = .external
                try? await Task.sleep(for: .seconds(5))
                continue
            }
            guard let lock = try? PortLock.acquire(PortLock.bridgeStartup) else {
                state = .waiting
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            // Recheck after gaining ownership: the previous owner may have just finished starting.
            if await Self.isHealthy() {
                lock.release()
                continue
            }
            startupLock = lock
            do {
                try await serve()
                state = .running
            } catch {
                state = .failed(error.localizedDescription)
                startupLock?.release()
                startupLock = nil
            }
            task = nil
            return
        }
    }

    private func serve() async throws {
        state = .preparing("Preparing the voice model…", fraction: nil)
        let manager = try await BridgeServer.prepare { [weak self] progress in
            Task { @MainActor in self?.show(progress) }
        }
        let app = try await BridgeServer.makeApplication(manager: manager)
        do {
            try await app.startup()
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        self.app = app
        // Vapor's serve command takes over SIGTERM and SIGINT and only reports them through
        // `running`, which nothing else here waits on; quit as the signal asks.
        Task { [weak self] in
            try? await app.running?.onStop.get()
            guard let self, self.app === app else { return }
            await self.stop()
            NSApp.terminate(nil)
        }
    }

    private func show(_ progress: BridgeProgress) {
        switch progress {
        case .downloadingModel(let fraction):
            state = .preparing("Downloading the voice model…", fraction: fraction)
        case .installingVoice(let voice):
            state = .preparing("Installing voice \(voice)…", fraction: nil)
        case .loadingModel:
            state = .preparing("Loading the voice model…", fraction: nil)
        }
    }

    static func isHealthy() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(BridgeServer.port)/v1/audio/health")!)
        request.timeoutInterval = 1
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try? JSONDecoder().decode([String: String].self, from: data)
        else { return false }
        return body["status"] == "ready"
    }
}
