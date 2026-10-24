@testable import AgenticVoiceKit
import Foundation
import Testing

struct VoiceServiceTests {
    @Test func normalizesWhitespaceBeforeSpeaking() throws {
        #expect(try VoiceService.prepareSpeechText("  Review\ncomplete.   Two issues.  ", maxChars: 100) == "Review complete. Two issues.")
    }

    @Test func rejectsEmptySpeech() {
        #expect(throws: AgenticVoiceError("Spoken text cannot be empty.")) { try VoiceService.prepareSpeechText("   ", maxChars: 100) }
    }

    @Test func rejectsTextAboveTheLimit() {
        let error = #expect(throws: AgenticVoiceError.self) { try VoiceService.prepareSpeechText("123456", maxChars: 5) }
        #expect(error?.message.contains("Summarize before speaking") == true)
    }

    @Test func keepsShortTextInOneChunk() {
        #expect(VoiceService.chunk("Review complete. Two issues.", limit: 320) == ["Review complete. Two issues."])
    }

    @Test func packsSentencesIntoChunksWithinTheLimit() {
        #expect(VoiceService.chunk("One two. Three four. Five six.", limit: 20) == ["One two. Three four.", "Five six."])
    }

    @Test func splitsALongSentenceBetweenWords() {
        #expect(VoiceService.chunk("alpha beta gamma delta epsilon zeta", limit: 12) == ["alpha beta", "gamma delta", "epsilon zeta"])
    }

    /// A real TTS endpoint and a real player whose command blocks until the test lets it finish.
    final class Fixture: Sendable {
        let directory: TemporaryDirectory
        let tts: TestHTTPServer
        let player: String
        let lockPort = freePort()
        let synthesized = Counter()

        init(playerExitStatus: Int = 0) async throws {
            let directory = try TemporaryDirectory()
            player = try directory.write("player", """
                #!/bin/bash
                touch '\(directory.path("playing"))'
                while [ ! -f '\(directory.path("finish"))' ]; do sleep 0.01; done
                exit \(playerExitStatus)
                """, mode: 0o755)
            let synthesized = self.synthesized
            tts = try await TestHTTPServer { _ in
                _ = synthesized.increment()
                return (200, "RIFF")
            }
            self.directory = directory
        }

        func voice(maxChars: Int = 100) -> VoiceService {
            VoiceService(
                tts: TTSClient(baseURL: tts.url, voice: "am_michael", language: "en-US", speed: 1),
                player: AudioPlayer(command: player, lockPort: lockPort),
                maxChars: maxChars
            )
        }

        func playing() async throws { try await eventually { directory.exists("playing") } }
        func finish() throws { try directory.write("finish", "") }
        deinit { tts.close() }
    }

    @Test func reportsBusyWithoutSynthesizingWhileAnotherSessionSpeaks() async throws {
        let fixture = try await Fixture()
        let first = Task { try await fixture.voice().speak("First message.") }
        try await fixture.playing()
        #expect(try await fixture.voice().speak("Second message.") == .busy)
        #expect(fixture.synthesized.value == 1)
        try fixture.finish()
        #expect(try await first.value == .spoken)
        #expect(try await fixture.voice().speak("Third message.") == .spoken)
        #expect(fixture.synthesized.value == 2)
    }

    @Test func synthesizesEveryChunkOfLongText() async throws {
        let fixture = try await Fixture()
        try fixture.finish()
        let sentence = String(repeating: "word ", count: 40) + "end."
        let text = Array(repeating: sentence, count: 3).joined(separator: " ")
        #expect(try await fixture.voice(maxChars: 1200).speak(text) == .spoken)
        #expect(fixture.synthesized.value == 3)
    }

    @Test func releasesTheSpeakerAfterAPlaybackFailure() async throws {
        let fixture = try await Fixture(playerExitStatus: 1)
        try fixture.finish()
        let error = await #expect(throws: AgenticVoiceError.self) { try await fixture.voice().speak("Failing message.") }
        #expect(error?.message.contains("Audio playback failed") == true)
        let lock = try PortLock.acquire(fixture.lockPort)
        #expect(lock != nil, "speaker lock should be free after a failure")
    }

    @Test func aPortLockIsFreeAgainOnceReleased() throws {
        let port = freePort()
        let held = try #require(try PortLock.acquire(port))
        #expect(try PortLock.acquire(port) == nil)
        held.release()
        #expect(try PortLock.acquire(port) != nil)
    }

    @Test func reportsTTSFailuresWithTheResponse() async throws {
        let server = try await TestHTTPServer { _ in (500, "model not loaded") }
        defer { server.close() }
        let client = TTSClient(baseURL: server.url, voice: "am_michael", language: "en-US", speed: 1)
        await #expect(throws: AgenticVoiceError("TTS request failed with HTTP 500: model not loaded")) { try await client.synthesize("Hi.") }
    }
}
