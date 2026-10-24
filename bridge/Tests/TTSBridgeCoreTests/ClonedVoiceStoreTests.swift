import Testing
import TTSBridgeCore

struct ClonedVoiceStoreTests {
    @Test(arguments: [("Max", "clone_max"), ("Max Müller", "clone_maxmuller"), ("Voice 2", "clone_voice2"), ("../../etc", "clone_etc")])
    func namesBecomeSafeIds(name: String, id: String) throws {
        #expect(try ClonedVoiceStore.id(forName: name) == id)
        #expect(ClonedVoiceStore.isValid(id))
    }

    @Test(arguments: ["", "  ", "../", "日本"])
    func rejectsNamesWithoutLettersOrDigits(name: String) {
        #expect(throws: ClonedVoiceStoreError.self) { try ClonedVoiceStore.id(forName: name) }
    }

    @Test(arguments: ["af_bella", "clone_", "clone_Max", "clone_../x", "clone_max.bin", "clone_max_2"])
    func onlyCloneIdsAreValid(id: String) {
        #expect(!ClonedVoiceStore.isValid(id))
    }

    @Test func clonedAndKokoroIdsNeverOverlap() {
        #expect(VoiceCatalog.voices.allSatisfy { !ClonedVoiceStore.isValid($0.id) })
    }

    @Test func clonedVoicesReadAsYourVoice() {
        let voice = Voice(id: "clone_max")
        #expect(voice.name == "Max")
        #expect(voice.accent == "Your voice")
    }
}
