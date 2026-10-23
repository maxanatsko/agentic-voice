import Foundation
import TTSBridgeCore

func logLine(_ message: String) {
    FileHandle.standardError.write("TTSBridge: \(message)\n".data(using: .utf8)!)
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "install-voice" {
    guard arguments.count == 2 else {
        logLine("usage: TTSBridge install-voice <voice-id, e.g. af_bella>")
        exit(64)
    }
    do {
        try await VoiceStore.install(arguments[1])
        print("installed: \(VoiceStore.directory.appendingPathComponent("\(arguments[1]).bin").path)")
        exit(0)
    } catch {
        logLine(error.localizedDescription)
        exit(1)
    }
}

logLine("loading Kokoro-ANE model (first run downloads it, may take a while)...")
let manager = try await BridgeServer.prepare()
logLine("model ready")

let app = try await BridgeServer.makeApplication(manager: manager)
do {
    try await app.execute()
} catch {
    try? await app.asyncShutdown()
    throw error
}
try await app.asyncShutdown()
