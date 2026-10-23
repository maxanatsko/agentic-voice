import AppKit
import SwiftUI
import TTSBridgeCore

/// Opens the Settings window. A plain NSWindow, because SwiftUI's Settings and Window scenes
/// are unreliable in an app that has only a menu bar item.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(host: BridgeHost) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: SettingsModel(host: host), host: host)))
            window.title = "Agentic Voice Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 560, height: 520))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @StateObject var model: SettingsModel
    @ObservedObject var host: BridgeHost

    var body: some View {
        TabView {
            GeneralTab(model: model, host: model.host).tabItem { Label("General", systemImage: "gearshape") }
            VoicesTab(model: model, host: model.host).tabItem { Label("Voices", systemImage: "waveform") }
            ClientsTab(model: model).tabItem { Label("Clients", systemImage: "puzzlepiece.extension") }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 460)
        .task { await model.load() }
        // First-run preparation installs the default voice; pick it up once the engine is ready.
        .onChange(of: model.engineReady) { _, ready in
            if ready { model.refreshVoices() }
        }
        .alert("Agentic Voice", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
    }
}

struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var host: BridgeHost
    @State private var speed = 1.0

    var body: some View {
        Form {
            Section("Speech") {
                Picker("Voice", selection: Binding(get: { model.selectedVoice }, set: { model.select(voice: $0) })) {
                    ForEach(VoiceCatalog.voices.filter { model.installedVoices.contains($0.id) }) { voice in
                        Text("\(voice.name) — \(voice.accent)").tag(voice.id)
                    }
                }
                LabeledContent("Speed") {
                    HStack {
                        Slider(value: $speed, in: 0.5...2.0, step: 0.05)
                        Text(String(format: "%.2f×", speed)).monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                Text("Applies to every agent on its next spoken message. TTS_VOICE or VOICE_SPEED in .env or the environment override these.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Voice engine") {
                Text(host.state.summary)
                if case .failed = host.state {
                    Button("Retry") { host.start() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { speed = model.speed }
        .onChange(of: speed) { _, speed in
            model.set(speed: speed)
            // A failed save leaves the setting unchanged; show that rather than the attempt.
            if model.settings.speed ?? 1.0 != (speed * 100).rounded() / 100 { self.speed = model.speed }
        }
        .onChange(of: model.settings) { _, settings in speed = settings.speed ?? 1.0 }
    }
}

struct VoicesTab: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var host: BridgeHost

    var body: some View {
        List(VoiceCatalog.voices) { voice in
            HStack {
                VStack(alignment: .leading) {
                    Text(voice.name) + Text(voice.id == model.selectedVoice ? "  (default)" : "").foregroundColor(.secondary)
                    Text("\(voice.accent) · \(voice.id)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.busyVoices.contains(voice.id) {
                    ProgressView().controlSize(.small)
                } else if model.installedVoices.contains(voice.id) {
                    Button("Preview") { Task { await model.play(voice) } }
                        .disabled(!model.engineReady || model.previewing)
                    Button("Delete") { model.remove(voice) }
                        .disabled(voice.id == model.selectedVoice)
                } else {
                    Button("Install") { Task { await model.install(voice) } }
                }
            }
        }
        .onAppear { model.refreshVoices() }
        .safeAreaInset(edge: .bottom) {
            Text("Voices download from hexgrad/Kokoro-82M (about 0.5 MB each).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ClientsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading) {
            List(model.clients) { client in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.name)
                        Text(statusText(client)).font(.caption).foregroundStyle(.secondary)
                        if let error = client.error {
                            Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                        } else if let note = client.note {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if client.installed {
                        if !client.current {
                            Button("Update") { Task { await model.install(client: client) } }
                        }
                        Button("Uninstall") { Task { await model.uninstall(client: client) } }
                    } else {
                        Button("Install") { Task { await model.install(client: client) } }
                    }
                }
                .disabled(model.busyClients)
            }
            Text("Restart a client after installing or uninstalling. Original config files are backed up once as <file>.agentic-voice-backup.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func statusText(_ client: ClientStatus) -> String {
        switch (client.installed, client.current) {
        case (true, true): return "Installed"
        case (true, false): return "Installed with outdated paths"
        case (false, _): return client.detected ? "Not installed" : "Not installed (not detected on this Mac)"
        }
    }
}
