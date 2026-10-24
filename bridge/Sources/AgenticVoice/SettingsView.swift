import AgenticVoiceKit
import AppKit
import SwiftUI
import TTSBridgeCore

/// Opens the Settings window: a plain NSWindow, because SwiftUI's Settings and Window scenes
/// are unreliable in an app that has only a menu bar item.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(model: SettingsModel) {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model, host: model.host))
            // Lets the split view's sidebar run under the titlebar, as in System Settings.
            controller.sceneBridgingOptions = .all
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.title = "Agentic Voice"
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 720, height: 560))
            window.center()
            self.window = window
        }
        // Reread on every open: settings and clients may have changed from the terminal since.
        Task { await model.load() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The sidebar's entries, with their System Settings-style icon and header.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case voices = "Voices"
    case clients = "Clients"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .voices: return "person.wave.2"
        case .clients: return "apple.terminal"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .voices: return .purple
        case .clients: return .blue
        }
    }

    var summary: String {
        switch self {
        case .general: return "Choose the voice and speed agents speak with, and check the voice engine."
        case .voices: return "Clone your own voice, or install, preview and remove the built-in ones."
        case .clients: return "Connect Agentic Voice to the coding agents on this Mac."
        }
    }
}

/// A white symbol on a colored rounded square, like System Settings' icons.
struct PaneIcon: View {
    let pane: SettingsPane
    var size: CGFloat = 24

    var body: some View {
        // Fitted into a fixed inset, so wide and tall symbols sit with the same margin.
        Image(systemName: pane.symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(size * 0.18)
            .frame(width: size, height: size)
            .background(pane.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var host: BridgeHost
    @State private var selection = SettingsPane.general

    var body: some View {
        NavigationSplitView {
            // A pane is always selected; deselecting would leave the sidebar and detail disagreeing.
            List(SettingsPane.allCases, selection: Binding(get: { selection }, set: { if let pane = $0 { selection = pane } })) { pane in
                Label { Text(pane.rawValue) } icon: { PaneIcon(pane: pane) }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            let pane = selection
            Form {
                Section {
                    VStack(spacing: 6) {
                        PaneIcon(pane: pane, size: 64)
                        Text(pane.rawValue).font(.title.bold())
                        Text(pane.summary).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                switch pane {
                case .general: GeneralTab(model: model, host: host)
                case .voices: VoicesTab(model: model, host: host)
                case .clients: ClientsTab(model: model)
                }
            }
            .formStyle(.grouped)
            // A Form per pane, so each opens scrolled to the top.
            .id(pane)
            .onAppear { model.refreshVoices() }
            .navigationTitle(pane.rawValue)
            // The pane header already names it, as in System Settings.
            .toolbar(removing: .title)
        }
        .frame(minWidth: 640, minHeight: 420)
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
        Group {
            Section {
                Picker("Voice", selection: Binding(get: { model.selectedVoice }, set: { model.select(voice: $0) })) {
                    ForEach(model.voiceChoices) { voice in
                        Text(model.isInstalled(voice) ? "\(voice.name) — \(voice.accent)" : "\(voice.name) — not installed").tag(voice.id)
                    }
                }
                LabeledContent("Speed") {
                    HStack {
                        // Saved when the drag ends, not on every step.
                        Slider(value: $speed, in: 0.5...2.0, step: 0.05) {
                            Text("Speed")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise")
                        } maximumValueLabel: {
                            Image(systemName: "hare")
                        } onEditingChanged: { editing in
                            guard !editing else { return }
                            model.set(speed: speed)
                            // A failed save leaves the setting unchanged; show that rather than the attempt.
                            speed = model.speed
                        }
                        .labelsHidden()
                        .onAppear { speed = model.speed }
                        .onChange(of: model.settings) { _, settings in speed = settings.speed ?? 1.0 }
                        Text(String(format: "%.2f×", speed)).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                Text("Speech")
            } footer: {
                Text("Applies to every agent on its next spoken message. Cloned voices speak at their natural pace; speed applies to built-in voices. TTS_VOICE or VOICE_SPEED in .env or the environment override these.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Voice Engine") {
                LabeledContent {
                    if case .failed = host.state {
                        Button("Retry") { host.start() }
                    }
                } label: {
                    Label { Text(host.state.summary) } icon: { EngineStatusIcon(state: host.state) }
                }
            }
        }
    }
}

/// A status light for the voice engine, like the ones in system Settings.
struct EngineStatusIcon: View {
    let state: BridgeHost.State

    var body: some View {
        switch state {
        case .running, .external:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .starting, .waiting, .preparing:
            ProgressView().controlSize(.small)
        }
    }
}

struct VoicesTab: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var host: BridgeHost
    @State private var cloning = false

    /// The catalog grouped by accent, in catalog order.
    private var accents: [(name: String, voices: [Voice])] {
        VoiceCatalog.voices.reduce(into: []) { groups, voice in
            if groups.last?.name == voice.accent {
                groups[groups.count - 1].voices.append(voice)
            } else {
                groups.append((voice.accent, [voice]))
            }
        }
    }

    var body: some View {
        let accents = accents
        Group {
            Section {
                ForEach(model.clonedVoices) { voice in row(voice) }
                Button("Clone a Voice…", systemImage: "plus.circle") { cloning = true }
            } header: {
                Text("Your Voices")
            } footer: {
                Text("Cloned voices speak with PocketTTS by Kyutai, on this Mac.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(accents, id: \.name) { accent in
                Section {
                    ForEach(accent.voices) { voice in row(voice) }
                } header: {
                    Text(accent.name)
                } footer: {
                    if accent.name == accents.last?.name {
                        Text("Voices download from hexgrad/Kokoro-82M (about 0.5 MB each).")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $cloning) {
            CloneVoiceView(model: model) { cloning = false }
                .frame(width: 520, height: 620)
        }
    }

    private func row(_ voice: Voice) -> some View {
        LabeledContent {
            if model.busyVoices.contains(voice.id) {
                ProgressView().controlSize(.small)
            } else if model.isInstalled(voice) {
                HStack(spacing: 6) {
                    Button("Preview", systemImage: "play.fill") { Task { await model.play(voice) } }
                        .disabled(!model.engineReady || model.previewing)
                    // The engine reinstalls the default voice, and af_heart, which ships with the model, on its next start.
                    Button("Delete", systemImage: "trash", role: .destructive) { model.remove(voice) }
                        .disabled(voice.id == model.selectedVoice || voice.id == VoiceCatalog.defaultVoice || voice.id == "af_heart")
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
            } else {
                Button("Install", systemImage: "arrow.down.circle") { Task { await model.install(voice) } }
                    .buttonBorderShape(.capsule)
            }
        } label: {
            Text(voice.name)
            Text(voice.id == model.selectedVoice ? "\(voice.id) · In use" : voice.id)
        }
    }
}

struct ClientsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Group {
            Section {
                if model.clients.isEmpty {
                    if model.busyClients {
                        HStack {
                            Spacer()
                            ProgressView().controlSize(.small)
                            Spacer()
                        }
                    } else {
                        LabeledContent("Couldn't check the clients.") {
                            Button("Retry") { Task { await model.load() } }
                        }
                    }
                }
                ForEach(model.clients) { client in row(client) }
            } footer: {
                Text("Restart a client after installing or uninstalling. Original config files are backed up once as <file>.agentic-voice-backup.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ client: ClientStatus) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                if client.installed {
                    if !client.current {
                        Button("Update") { Task { await model.install(client: client) } }
                    }
                    Button("Uninstall") { Task { await model.uninstall(client: client) } }
                } else {
                    Button("Install") { Task { await model.install(client: client) } }
                }
            }
            .buttonBorderShape(.capsule)
            .disabled(model.busyClients)
        } label: {
            let status = status(client)
            Label {
                Text(client.name)
                Text(status.text)
                if let error = client.error {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                } else if let note = client.note {
                    Text(note)
                }
            } icon: {
                Image(systemName: status.symbol).foregroundStyle(status.color)
            }
        }
    }

    private func status(_ client: ClientStatus) -> (text: String, symbol: String, color: Color) {
        switch (client.installed, client.current) {
        case (true, true): return ("Installed", "checkmark.circle.fill", .green)
        case (true, false): return ("Installed with outdated paths", "exclamationmark.circle.fill", .orange)
        case (false, _): return (client.detected ? "Not installed" : "Not installed (not detected on this Mac)", "circle.dashed", .secondary)
        }
    }
}
