import AppKit
import SwiftUI

@main
struct AgenticVoiceApp: App {
    @StateObject private var host: BridgeHost

    init() {
        let host = BridgeHost()
        _host = StateObject(wrappedValue: host)
        host.start()
    }

    var body: some Scene {
        MenuBarExtra("Agentic Voice", systemImage: "waveform") {
            MenuContent(host: host)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var host: BridgeHost
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        Text(host.state.summary)
        if case .failed = host.state {
            Button("Retry", systemImage: "arrow.clockwise") { host.start() }
        }
        if let loginItemError {
            Text(loginItemError)
        }
        Divider()
        Button("Settings…", systemImage: "gearshape") { SettingsWindow.show(host: host) }
            .keyboardShortcut(",")
        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, enabled in
                // Resetting the toggle after a failure lands here too; there is nothing to change then.
                guard enabled != LoginItem.isEnabled else { return }
                do {
                    try LoginItem.set(enabled)
                    loginItemError = nil
                } catch {
                    loginItemError = "Launch at login: \(error.localizedDescription)"
                    launchAtLogin = LoginItem.isEnabled
                }
            }
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
