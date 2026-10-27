/// A Kokoro-82M voice whose accent matches the English text frontend, a cloned voice, or a
/// Voxtral preset.
public struct Voice: Identifiable, Hashable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }

    public var isCloned: Bool { ClonedVoiceStore.isValid(id) }
    public var isVoxtral: Bool { VoxtralVoices.isValid(id) }

    /// "Michael", from the id's suffix; "Neutral male" for a Voxtral preset.
    public var name: String {
        if isVoxtral {
            let preset = id.dropFirst(VoxtralVoices.prefix.count).replacingOccurrences(of: "_", with: " ")
            return preset.prefix(1).uppercased() + preset.dropFirst()
        }
        let suffix = id.split(separator: "_").last.map(String.init) ?? id
        return suffix.prefix(1).uppercased() + suffix.dropFirst()
    }

    /// "US male", from the id's two-letter prefix.
    public var accent: String {
        if isCloned { return "Your voice" }
        if isVoxtral { return "Voxtral" }
        let accent = id.hasPrefix("a") ? "US" : "UK"
        return id.dropFirst().hasPrefix("f") ? "\(accent) female" : "\(accent) male"
    }
}

public enum VoiceCatalog {
    public static let defaultVoice = "am_michael"

    /// The US (`af_`/`am_`) and UK (`bf_`/`bm_`) voices. Other Kokoro prefixes are other
    /// languages and sound wrong when read through the English frontend.
    public static let voices: [Voice] = [
        "af_heart", "af_alloy", "af_aoede", "af_bella", "af_jessica", "af_kore", "af_nicole",
        "af_nova", "af_river", "af_sarah", "af_sky",
        "am_adam", "am_echo", "am_eric", "am_fenrir", "am_liam", "am_michael", "am_onyx",
        "am_puck", "am_santa",
        "bf_alice", "bf_emma", "bf_isabella", "bf_lily",
        "bm_daniel", "bm_fable", "bm_george", "bm_lewis",
    ].map(Voice.init(id:))
}
