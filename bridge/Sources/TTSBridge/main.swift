import Vapor
import FluidAudio

let defaultVoice = "am_michael"

FileHandle.standardError.write("TTSBridge: loading Kokoro-ANE model (first run downloads it, may take a while)...\n".data(using: .utf8)!)

let manager = KokoroAneManager()
try await manager.initialize(preloadVoices: [defaultVoice])

FileHandle.standardError.write("TTSBridge: model ready\n".data(using: .utf8)!)

let app = try await Application.make(.detect())
app.http.server.configuration.hostname = "127.0.0.1"
app.http.server.configuration.port = 9000

struct SynthesizeRequest: Content {
    let text: String
    let voice: String?
    let language: String?
    let speed: String?
}

app.on(.POST, "v1", "audio", "synthesize") { req async throws -> Response in
    let payload = try req.content.decode(SynthesizeRequest.self)
    let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
        throw Abort(.badRequest, reason: "text is required")
    }

    let requestedVoice = payload.voice?.trimmingCharacters(in: .whitespacesAndNewlines)
    let voice = (requestedVoice?.isEmpty == false ? requestedVoice! : defaultVoice)

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

    let wavData = try await manager.synthesize(text: text, voice: voice, speed: speed)

    var headers = HTTPHeaders()
    headers.replaceOrAdd(name: .contentType, value: "audio/wav")
    return Response(status: .ok, headers: headers, body: .init(data: wavData))
}

app.get { req async -> String in
    "TTSBridge (FluidAudio Kokoro-ANE) is running.\n"
}

try await app.execute()
