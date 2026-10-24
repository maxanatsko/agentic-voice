@testable import AgenticVoiceKit
import Foundation
import Testing

struct ConfigTests {
    @Test func missingSettingsFileMeansNoSettings() throws {
        #expect(try Config.readSettings(at: URL(fileURLWithPath: "/tmp/agentic-voice-missing/config.json")) == Settings())
    }

    @Test func readsVoiceAndSpeedAndIgnoresUnknownKeys() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.write("config.json", #"{"voice": " af_bella ", "speed": 1.25, "theme": "dark"}"#)
        #expect(try Config.readSettings(at: URL(fileURLWithPath: file)) == Settings(voice: "af_bella", speed: 1.25))
    }

    @Test(arguments: ["{not json", "[]", #"{"voice": ""}"#, #"{"voice": 3}"#, #"{"speed": 0}"#, #"{"speed": "fast"}"#, #"{"speed": true}"#])
    func rejectsInvalidSettingsNamingTheFile(content: String) throws {
        let directory = try TemporaryDirectory()
        let file = try directory.write("config.json", content)
        let error = #expect(throws: AgenticVoiceError.self) { try Config.readSettings(at: URL(fileURLWithPath: file)) }
        #expect(error?.message.contains(file) == true)
    }

    @Test func settingsOverrideDefaults() throws {
        let config = try Config.load(environment: [:], settings: Settings(voice: "bf_emma", speed: 1.5))
        #expect(config.voice == "bf_emma")
        #expect(config.speed == 1.5)
        let defaults = try Config.load(environment: [:], settings: Settings())
        #expect(defaults.voice == "am_michael")
        #expect(defaults.speed == 1.0)
        #expect(defaults.ttsURL == "http://127.0.0.1:9000")
    }

    @Test func environmentOverridesSettings() throws {
        let config = try Config.load(environment: ["TTS_VOICE": "am_adam", "VOICE_SPEED": "0.8"], settings: Settings(voice: "bf_emma", speed: 1.5))
        #expect(config.voice == "am_adam")
        #expect(config.speed == 0.8)
        #expect(throws: AgenticVoiceError.self) { try Config.load(environment: ["VOICE_MAX_CHARS": "0"], settings: Settings()) }
    }

    @Test func parsesDotEnv() {
        let values = Config.parseDotEnv("# comment\nTTS_URL=http://host:9000\nexport TTS_VOICE = \"af_bella\"\n\nVOICE_SPEED='1.2'\nnot a pair\n")
        #expect(values == ["TTS_URL": "http://host:9000", "TTS_VOICE": "af_bella", "VOICE_SPEED": "1.2"])
    }

    @Test func dotEnvStripsInlineComments() throws {
        let values = Config.parseDotEnv("VOICE_SPEED=1.2 # faster\nTTS_URL=http://host:9000#remote\nTTS_VOICE=\"af # bella\" # quoted\nTTS_LANGUAGE='en-US'# uk later\n")
        #expect(values == ["VOICE_SPEED": "1.2", "TTS_URL": "http://host:9000", "TTS_VOICE": "af # bella", "TTS_LANGUAGE": "en-US"])
        #expect(try Config.load(environment: values, settings: Settings()).speed == 1.2)
    }

    @Test func onlyTheBundledLoopbackEndpointIsManaged() {
        for url in ["http://127.0.0.1:9000", "http://localhost:9000/", "http://[::1]:9000"] {
            #expect(Config.isBundledTTSURL(url), "\(url)")
        }
        for url in ["https://127.0.0.1:9000", "http://example.com:9000", "http://127.0.0.1:9001", "http://localhost:9000/tts", "http://u:p@127.0.0.1:9000"] {
            #expect(!Config.isBundledTTSURL(url), "\(url)")
        }
    }
}
