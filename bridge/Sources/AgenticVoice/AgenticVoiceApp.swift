import AppKit
import SwiftUI

@main
struct AgenticVoiceApp: App {
    @StateObject private var host: BridgeHost
    /// Shared by Settings and onboarding, so the two windows never disagree.
    @StateObject private var model: SettingsModel

    init() {
        let host = BridgeHost()
        let model = SettingsModel(host: host)
        _host = StateObject(wrappedValue: host)
        _model = StateObject(wrappedValue: model)
        host.start()
        // No settings file yet means nobody has set the app up; finishing onboarding writes one.
        if !FileManager.default.fileExists(atPath: AppSettings.url.path) {
            Task { @MainActor in OnboardingWindow.show(model: model) }
        }
    }

    var body: some Scene {
        MenuBarExtra("Agentic Voice", systemImage: "waveform") {
            MenuContent(host: host, model: model)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var host: BridgeHost
    let model: SettingsModel

    var body: some View {
        Text(host.state.summary)
        if case .failed = host.state {
            Button("Retry", systemImage: "arrow.clockwise") { host.start() }
        }
        Divider()
        Button("Settings…", systemImage: "gearshape") { SettingsWindow.show(model: model) }
            .keyboardShortcut(",")
        Button("Welcome…", systemImage: "hand.wave") { OnboardingWindow.show(model: model) }
        LaunchAtLoginToggle()
        Divider()
        Button("Quit Agentic Voice", systemImage: "power") {
            Task {
                await host.stop()
                NSApp.terminate(nil)
            }
        }
        .keyboardShortcut("q")
    }
}
