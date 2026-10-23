import AppKit
import TTSBridgeCore

/// State and actions behind the Settings window. Blocking work runs off the main actor.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var settings = AppSettings()
    @Published private(set) var installedVoices: Set<String> = []
    @Published private(set) var busyVoices: Set<String> = []
    @Published private(set) var node: Result<NodeInstall, Error>?
    @Published private(set) var clients: [ClientStatus] = []
    @Published private(set) var busyClients = false
    @Published var message: String?

    let host: BridgeHost
    private let preview = VoicePreview()
    private var shellPath: String?

    init(host: BridgeHost) {
        self.host = host
    }

    var selectedVoice: String { settings.voice ?? VoiceCatalog.defaultVoice }
    var speed: Double { settings.speed ?? 1.0 }

    var engineReady: Bool {
        host.state == .running || host.state == .external
    }

    func load() async {
        do {
            settings = try AppSettings.load()
        } catch {
            message = "Couldn't read \(AppSettings.url.path): \(error.localizedDescription)"
        }
        refreshVoices()
        await locateNode()
    }

    // MARK: Settings

    func select(voice: String) {
        settings.voice = voice
        save()
    }

    func set(speed: Double) {
        settings.speed = (speed * 100).rounded() / 100
        save()
    }

    private func save() {
        do {
            try settings.save()
        } catch {
            message = "Couldn't save settings: \(error.localizedDescription)"
        }
    }

    // MARK: Voices

    func refreshVoices() {
        installedVoices = Set(VoiceCatalog.voices.map(\.id).filter(VoiceStore.isInstalled))
    }

    func install(_ voice: Voice) async {
        busyVoices.insert(voice.id)
        defer { busyVoices.remove(voice.id) }
        do {
            try await VoiceStore.install(voice.id)
        } catch {
            message = "Couldn't install \(voice.name): \(error.localizedDescription)"
        }
        refreshVoices()
    }

    func remove(_ voice: Voice) {
        do {
            try VoiceStore.remove(voice.id)
        } catch {
            message = "Couldn't delete \(voice.name): \(error.localizedDescription)"
        }
        refreshVoices()
    }

    func play(_ voice: Voice) async {
        busyVoices.insert(voice.id)
        defer { busyVoices.remove(voice.id) }
        do {
            try await preview.play(voice, speed: speed)
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: Node and clients

    func locateNode() async {
        let located = await Task.detached { () -> (Result<NodeInstall, Error>, String) in
            (Result { try NodeLocator.locate() }, NodeLocator.loginShellPath())
        }.value
        node = located.0
        shellPath = located.1
        await runInstaller("status")
    }

    func chooseNode() async {
        let panel = NSOpenPanel()
        panel.message = "Choose a node binary (version \(NodeLocator.minimumMajor) or newer)"
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        NodeLocator.chosenPath = url.path
        await locateNode()
    }

    func useDetectedNode() async {
        NodeLocator.chosenPath = nil
        await locateNode()
    }

    func install(client: ClientStatus) async { await runInstaller("install", [client.id]) }
    func uninstall(client: ClientStatus) async { await runInstaller("uninstall", [client.id]) }

    private func runInstaller(_ command: String, _ ids: [String] = []) async {
        guard case .success(let node) = node, let path = shellPath else { return }
        busyClients = true
        defer { busyClients = false }
        let result = await Task.detached {
            Result { try ClientInstaller.run(command, clients: ids, node: node, path: path) }
        }.value
        switch result {
        case .success(let statuses):
            // A command for some clients reports only those; merge them into the full list.
            clients = clients.isEmpty ? statuses : clients.map { old in statuses.first { $0.id == old.id } ?? old }
        case .failure(let error):
            message = error.localizedDescription
        }
    }
}
