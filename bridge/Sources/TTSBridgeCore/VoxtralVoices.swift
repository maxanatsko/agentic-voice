import AudioCommon
import FluidAudio
import Foundation
import VoxtralTTS

/// Mistral's Voxtral 4B TTS preset voices, spoken with speech-swift on MLX as `voxtral_<preset>`
/// voices. The weights are CC BY-NC 4.0: personal, non-commercial use only. One model download
/// (about 2.5 GB) covers every preset, so the family is downloaded or not as a whole.
public enum VoxtralVoices {
    public static let prefix = "voxtral_"
    /// The English presets; the checkpoint's other presets are for other languages.
    public static let presets = ["neutral_male", "neutral_female", "casual_male", "casual_female", "cheerful_female"]
    public static let voices = presets.map { Voice(id: prefix + $0) }

    static let modelId = VoxtralTTSModel.defaultModelId
    /// Everything `VoxtralTTSModel.fromBundle` reads, including all 20 preset embeddings it checks.
    static let files = ["config.json", "tekken.json", "model.safetensors"]
        + VoxtralTTSModel.voices.map { "voice_embedding/\($0).safetensors" }

    /// speech-swift's Hugging Face cache, so a model downloaded by its own tools is reused.
    public static var directory: URL {
        get throws { try HuggingFaceDownloader.getCacheDirectory(for: modelId) }
    }

    /// Any `voxtral_` id, so an unknown preset gets a Voxtral error instead of a Kokoro one.
    public static func isValid(_ id: String) -> Bool {
        id.hasPrefix(prefix)
    }

    /// `voxtral_neutral_male` → `neutral_male`; nil for an id that names no English preset.
    public static func preset(for id: String) -> String? {
        guard isValid(id) else { return nil }
        let preset = String(id.dropFirst(prefix.count))
        return presets.contains(preset) ? preset : nil
    }

    public static func isDownloaded() -> Bool {
        guard let directory = try? directory else { return false }
        return isDownloaded(in: directory)
    }

    static func isDownloaded(in directory: URL) -> Bool {
        files.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    /// Downloads the model without loading it; the bridge loads it on the first Voxtral request.
    public static func download(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try await HuggingFaceDownloader.downloadFiles(
            modelId: modelId, to: directory, files: files, progressHandler: { progress?($0) })
    }

    /// Speaks Voxtral voices. The model (about 3 GB in memory) loads on the first request for one
    /// and stays loaded, so a bridge that only speaks other voices never pays for it.
    actor Speaker {
        private var model: VoxtralTTSModel?

        func synthesize(text: String, preset: String) async throws -> Data {
            let model = try loadedModel()
            let samples = try await model.generate(text: text, voice: preset)
            // At its own level, about 13 dB below Kokoro: peak-normalizing makes the model's noise
            // floor audible as hiss.
            return try AudioWAV.data(from: samples, sampleRate: Double(model.sampleRate), normalize: false)
        }

        private func loadedModel() throws -> VoxtralTTSModel {
            if let model { return model }
            let model = try VoxtralTTSModel.fromBundle(VoxtralVoices.directory)
            self.model = model
            return model
        }
    }
}
