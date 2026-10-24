import AppKit
import SwiftUI
import TTSBridgeCore

/// Opens onboarding: a plain NSWindow, for the same reason as `SettingsWindow`.
@MainActor
enum OnboardingWindow {
    private static var window: NSWindow?

    static func show(model: SettingsModel) {
        if window == nil {
            let controller = NSHostingController(rootView: OnboardingView(model: model, host: model.host) { OnboardingWindow.window?.close() })
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.title = "Welcome to Agentic Voice"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 580, height: 600))
            window.center()
            self.window = window
        }
        Task { await model.load() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome, voice, agents, finish

    var title: String {
        switch self {
        case .welcome: return "Welcome to Agentic Voice"
        case .voice: return "Choose a Voice"
        case .agents: return "Connect Your Agents"
        case .finish: return "You're All Set"
        }
    }

    var symbol: String {
        switch self {
        case .welcome: return "waveform"
        case .voice: return "person.wave.2"
        case .agents: return "apple.terminal"
        case .finish: return "checkmark.seal"
        }
    }

    var summary: String {
        switch self {
        case .welcome: return "Your coding agents speak short updates out loud, so you know when a task is done or needs you. Everything runs on this Mac."
        case .voice: return "Pick a built-in voice, or clone your own from a short recording."
        case .agents: return "Install Agentic Voice into the coding agents you use. Restart an agent after installing."
        case .finish: return "Change any of this later in Settings, from the waveform icon in the menu bar."
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var host: BridgeHost
    let onClose: () -> Void
    @State private var step = OnboardingStep.welcome
    @State private var cloning = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: step.symbol)
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(.tint)
                            .frame(height: 56)
                        Text(step.title).font(.title.bold())
                        Text(step.summary).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                switch step {
                case .welcome:
                    Section("Voice Engine") {
                        Label { Text(host.state.summary) } icon: { EngineStatusIcon(state: host.state) }
                        if case .failed = host.state {
                            Button("Retry") { host.start() }
                        }
                    }
                case .voice:
                    GeneralTab(model: model, host: host)
                    Section {
                        LabeledContent("Hear the selected voice") {
                            Button("Preview", systemImage: "play.fill") { Task { await model.play(Voice(id: model.selectedVoice)) } }
                                .disabled(!model.engineReady || model.previewing || !model.isInstalled(Voice(id: model.selectedVoice)))
                        }
                        LabeledContent("Sound like yourself") {
                            Button("Clone My Voice…", systemImage: "mic.fill") { cloning = true }
                        }
                    } footer: {
                        Text("More built-in voices are in Settings → Voices.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                case .agents:
                    ClientsTab(model: model)
                case .finish:
                    Section { LaunchAtLoginToggle() } footer: {
                        Text("Keeps the voice engine ready, so agents can speak as soon as they start.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .id(step)
            HStack {
                if step != .welcome {
                    Button("Back") { move(by: -1) }
                }
                Spacer()
                if step == .finish {
                    Button("Done") {
                        if model.finishOnboarding() { onClose() }
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { move(by: 1) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .onAppear { model.refreshVoices() }
        // First-run preparation installs the default voice; pick it up once the engine is ready.
        .onChange(of: model.engineReady) { _, ready in
            if ready { model.refreshVoices() }
        }
        .sheet(isPresented: $cloning) {
            CloneVoiceView(model: model) { cloning = false }
                .frame(width: 520, height: 620)
        }
        .alert("Agentic Voice", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
    }

    private func move(by offset: Int) {
        step = OnboardingStep(rawValue: step.rawValue + offset) ?? step
    }
}
