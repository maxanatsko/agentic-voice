import Foundation

/// Why an agent speaks: the speak tool's `kind` and the CLI's `--kind`.
public enum SpeechKind: String, CaseIterable, Codable, Sendable {
    case question, completion, alert, custom
}

/// One spoken message, as the speaking overlay shows it.
public struct Utterance: Codable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var kind: SpeechKind?
    /// The speaking process's working directory name.
    public var project: String?
    /// The speaking process, so the overlay can hide if it dies without saying it ended.
    public var pid: Int32

    public init(id: UUID = UUID(), text: String, kind: SpeechKind? = nil, project: String? = nil, pid: Int32 = getpid()) {
        self.id = id
        self.text = text
        self.kind = kind
        self.project = project
        self.pid = pid
    }
}

/// What a speaking process tells the Agentic Voice app, which shows the speaking overlay.
public enum SpeechEvent: Codable, Equatable, Sendable {
    /// Playback is starting.
    case started(Utterance)
    /// The utterance finished, failed or was cancelled.
    case ended(id: UUID)
}

/// Fire-and-forget distributed notifications: nothing happens when no app is listening.
public enum DistributedSpeechEvents {
    public static let name = Notification.Name("com.maxanatsko.agentic-voice.speech")

    /// The event travels as the notification's object, a JSON string.
    public static func post(_ event: SpeechEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        DistributedNotificationCenter.default().postNotificationName(
            name, object: String(decoding: data, as: UTF8.self), userInfo: nil, deliverImmediately: true)
    }

    public static func decode(_ notification: Notification) -> SpeechEvent? {
        guard let json = notification.object as? String else { return nil }
        return try? JSONDecoder().decode(SpeechEvent.self, from: Data(json.utf8))
    }
}
