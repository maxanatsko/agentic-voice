import AgenticVoiceKit
import Foundation
import TTSBridgeCore

/// State and actions behind the Settings window. Blocking work runs off the main actor.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var settings = AppSettings()
    @Published private(set) var installedVoices: Set<String> = []
    @Published private(set) var busyVoices: Set<String> = []
    @Published private(set) var previewing = false
    @Published private(set) var clients: [ClientStatus] = []
    @Published private(set) var busyClients = false
    @Published var message: String?

    let host: BridgeHost
    private var shellPath: String?
    /// Set when the settings file exists but can't be read; saving then would replace it.
    private var unreadableSettings: String?

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
            unreadableSettings = nil
        } catch {
            unreadableSettings = error.localizedDescription
            message = error.localizedDescription
        }
        refreshVoices()
        // Clients show as loading, not as failed, while the shell PATH resolves.
        busyClients = true
        shellPath = await Task.detached { ClientInstaller.loginShellPath() }.value
        busyClients = false
        await runInstaller(.status)
    }

    // MARK: Settings

    func select(voice: String) {
        guard voice != settings.voice else { return }
        save { $0.voice = voice }
    }

    func set(speed: Double) {
        let rounded = (speed * 100).rounded() / 100
        guard rounded != settings.speed else { return }
        save { $0.speed = rounded }
    }

    /// Publishes the change only once it's on disk, so the window never shows a value agents don't use.
    private func save(_ change: (inout AppSettings) -> Void) {
        if unreadableSettings != nil {
            // The user may have fixed or deleted the file since; apply the change to what's there now.
            do {
                settings = try AppSettings.load()
                unreadableSettings = nil
            } catch {
                unreadableSettings = error.localizedDescription
                message = "Not saved, so the existing file isn't replaced. \(error.localizedDescription)"
                return
            }
        }
        var next = settings
        change(&next)
        do {
            try next.save()
            settings = next
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
        // One preview at a time: a second would hit the speaking lock and look like another session.
        previewing = true
        busyVoices.insert(voice.id)
        defer {
            previewing = false
            busyVoices.remove(voice.id)
        }
        do {
            try await VoicePreview.play(voice, speed: speed)
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: Clients

    func install(client: ClientStatus) async { await runInstaller(.install, [client.id]) }
    func uninstall(client: ClientStatus) async { await runInstaller(.uninstall, [client.id]) }

    private func runInstaller(_ action: Clients.Action, _ ids: [String] = []) async {
        guard let path = shellPath else { return }
        busyClients = true
        defer { busyClients = false }
        let result = await Task.detached {
            Result { try ClientInstaller.run(action, clients: ids, path: path) }
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
