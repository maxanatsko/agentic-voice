import AVFoundation
import Foundation
import TTSBridgeCore

enum VoiceRecorderError: Error, LocalizedError {
    case denied
    case failed

    var errorDescription: String? {
        switch self {
        case .denied: return "Agentic Voice can't use the microphone. Allow it in System Settings → Privacy & Security → Microphone, or choose a recording instead."
        case .failed: return "Recording didn't start; check that a microphone is connected."
        }
    }
}

/// Records a voice sample for cloning into a temporary WAV file, stopping on its own once it
/// holds as much as PocketTTS uses.
@MainActor
final class VoiceRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    /// The finished sample, until it's discarded.
    @Published private(set) var recording: URL?
    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw VoiceRecorderError.denied }
        discard()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agentic-voice-sample-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record(forDuration: ClonedVoiceStore.usedSeconds) else { throw VoiceRecorderError.failed }
        self.recorder = recorder
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        recorder?.stop()
        finish()
    }

    /// Stops and deletes the sample; call once it has been cloned or is no longer wanted.
    func discard() {
        stop()
        if let recording { try? FileManager.default.removeItem(at: recording) }
        recording = nil
        elapsed = 0
    }

    private func tick() {
        guard let recorder else { return }
        if recorder.isRecording {
            elapsed = recorder.currentTime
        } else {
            // record(forDuration:) stopped it.
            elapsed = ClonedVoiceStore.usedSeconds
            finish()
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        isRecording = false
        if let recorder { recording = recorder.url }
        recorder = nil
    }
}
