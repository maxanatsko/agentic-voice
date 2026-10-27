import Foundation
import Testing
import Vapor
@testable import TTSBridgeCore

struct VoxtralVoicesTests {
    @Test(arguments: VoxtralVoices.presets)
    func idsMapToPresets(preset: String) {
        #expect(VoxtralVoices.preset(for: "voxtral_\(preset)") == preset)
    }

    @Test(arguments: ["voxtral_", "voxtral_bogus", "voxtral_fr_male", "neutral_male", "am_michael", "clone_max"])
    func otherIdsNameNoPreset(id: String) {
        #expect(VoxtralVoices.preset(for: id) == nil)
    }

    @Test func voxtralClonedAndKokoroIdsNeverOverlap() {
        #expect(VoiceCatalog.voices.allSatisfy { !VoxtralVoices.isValid($0.id) })
        #expect(VoxtralVoices.voices.allSatisfy { !ClonedVoiceStore.isValid($0.id) })
    }

    @Test func voxtralVoicesReadAsPresets() {
        let voice = Voice(id: "voxtral_neutral_male")
        #expect(voice.isVoxtral)
        #expect(voice.name == "Neutral male")
        #expect(voice.accent == "Voxtral")
    }

    @Test(arguments: [
        ("am_michael", BridgeServer.Engine.kokoro),
        ("clone_max", .cloned),
        ("voxtral_neutral_male", .voxtral(preset: "neutral_male")),
        ("voxtral_cheerful_female", .voxtral(preset: "cheerful_female")),
    ])
    func routesByVoiceId(voice: String, engine: BridgeServer.Engine) throws {
        #expect(try BridgeServer.engine(for: voice) == engine)
    }

    @Test func unknownVoxtralVoiceIsABadRequest() {
        #expect {
            try BridgeServer.engine(for: "voxtral_bogus")
        } throws: { error in
            (error as? Abort)?.status == .badRequest
        }
    }

    @Test func downloadedOnlyWithEveryFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("voice_embedding"), withIntermediateDirectories: true)
        #expect(!VoxtralVoices.isDownloaded(in: directory))
        for file in VoxtralVoices.files.dropLast() {
            FileManager.default.createFile(atPath: directory.appendingPathComponent(file).path, contents: Data())
        }
        #expect(!VoxtralVoices.isDownloaded(in: directory))
        FileManager.default.createFile(atPath: directory.appendingPathComponent(VoxtralVoices.files.last!).path, contents: Data())
        #expect(VoxtralVoices.isDownloaded(in: directory))
    }
}
