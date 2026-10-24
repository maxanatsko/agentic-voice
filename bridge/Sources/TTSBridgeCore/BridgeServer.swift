import FluidAudio
import Vapor

/// What `BridgeServer.prepare` is doing, for progress display.
public enum BridgeProgress: Sendable {
    case downloadingModel(fraction: Double)
    case installingVoice(String)
    case loadingModel
}

/// The HTTP contract the Node client speaks:
/// `GET /v1/audio/health` and `POST /v1/audio/synthesize` (multipart `text`/`voice`/`language`/`speed`) → WAV.
/// Kokoro speaks the catalog voices; PocketTTS speaks cloned (`clone_`) voices.
public enum BridgeServer {
    public static let port = 9000

    /// Downloads whatever is missing and loads the model. Synthesis is available once this returns.
    /// Always prepares `VoiceCatalog.defaultVoice`, the voice a request without one gets.
    public static func prepare(
        progress: (@Sendable (BridgeProgress) -> Void)? = nil
    ) async throws -> KokoroAneManager {
        let defaultVoice = VoiceCatalog.defaultVoice
        let report: ProgressHandler = { progress?(.downloadingModel(fraction: $0.fractionCompleted)) }
        try await KokoroAneResourceDownloader.ensureModels(variant: .english, progressHandler: report)
        try await KokoroAneResourceDownloader.ensureG2PAssets(progressHandler: report)
        // FluidAudio hosts only af_heart; other voices must be converted from the official release first.
        if !VoiceStore.isInstalled(defaultVoice) {
            progress?(.installingVoice(defaultVoice))
            try await VoiceStore.install(defaultVoice)
        }
        progress?(.loadingModel)
        let manager = KokoroAneManager(defaultVoice: defaultVoice)
        try await manager.initialize(preloadVoices: [defaultVoice])
        return manager
    }

    /// Builds the server on 127.0.0.1. Start it with `execute()` (blocking) or `startup()`.
    public static func makeApplication(manager: KokoroAneManager, port: Int = port) async throws -> Application {
        // Fixed arguments: the host process's own command line is not for Vapor.
        let app = try await Application.make(Environment(name: "development", arguments: ["agentic-voice-bridge"]))
        app.http.server.configuration.hostname = "127.0.0.1"
        app.http.server.configuration.port = port
        let clonedVoices = ClonedVoiceStore.Speaker()

        // HTTP starts only after model initialization, so this endpoint is ready immediately.
        app.get("v1", "audio", "health") { _ async -> HealthResponse in
            HealthResponse(status: "ready")
        }

        app.on(.POST, "v1", "audio", "synthesize") { req async throws -> Response in
            let payload = try req.content.decode(SynthesizeRequest.self)
            let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw Abort(.badRequest, reason: "text is required")
            }

            let requestedVoice = payload.voice?.trimmingCharacters(in: .whitespacesAndNewlines)
            let voice = requestedVoice?.isEmpty == false ? requestedVoice! : VoiceCatalog.defaultVoice
            if ClonedVoiceStore.isValid(voice) {
                guard ClonedVoiceStore.isInstalled(voice) else {
                    throw Abort(.badRequest, reason: "cloned voice \(voice) doesn't exist; clone it again in Agentic Voice or run TTSBridge clone-voice")
                }
                // PocketTTS has no speed control; cloned voices speak at their natural pace.
                return wav(try await clonedVoices.synthesize(text: text, voice: voice))
            }
            guard VoiceStore.isInstalled(voice) else {
                throw Abort(.badRequest, reason: "voice \(voice) is not installed; install it in Agentic Voice or run TTSBridge install-voice \(voice)")
            }

            let requestedSpeed = payload.speed?.trimmingCharacters(in: .whitespacesAndNewlines)
            let speed: Float
            if let requestedSpeed, !requestedSpeed.isEmpty {
                guard let parsed = Float(requestedSpeed), parsed > 0 else {
                    throw Abort(.badRequest, reason: "speed must be a positive number")
                }
                speed = parsed
            } else {
                speed = KokoroAneConstants.defaultSpeed
            }

            return wav(try await manager.synthesize(text: text, voice: voice, speed: speed))
        }

        app.get { _ async -> String in
            "TTSBridge (FluidAudio Kokoro-ANE, PocketTTS for cloned voices) is running.\n"
        }

        return app
    }

    private static func wav(_ data: Data) -> Response {
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .contentType, value: "audio/wav")
        return Response(status: .ok, headers: headers, body: .init(data: data))
    }
}

struct SynthesizeRequest: Content {
    let text: String
    let voice: String?
    let language: String?
    let speed: String?
}

struct HealthResponse: Content {
    let status: String
}
