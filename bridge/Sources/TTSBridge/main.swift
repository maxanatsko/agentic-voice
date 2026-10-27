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

if arguments.first == "clone-voice" {
    guard arguments.count == 3 else {
        logLine("usage: TTSBridge clone-voice <name, e.g. max> <audio file, \(Int(ClonedVoiceStore.usedSeconds)) s or longer works best>")
        exit(64)
    }
    do {
        logLine("cloning (the first clone downloads the PocketTTS model, may take a while)...")
        print(try await ClonedVoiceStore.clone(name: arguments[1], from: URL(fileURLWithPath: arguments[2])))
        exit(0)
    } catch {
        logLine(error.localizedDescription)
        exit(1)
    }
}

if arguments.first == "download-voxtral" {
    guard arguments.count == 1 else {
        logLine("usage: TTSBridge download-voxtral (about 2.5 GB, personal use only: CC BY-NC 4.0)")
        exit(64)
    }
    do {
        logLine("downloading Voxtral TTS (about 2.5 GB)...")
        try await VoxtralVoices.download { logLine(String(format: "%.0f%%", $0 * 100)) }
        print("downloaded: \(try VoxtralVoices.directory.path)")
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
