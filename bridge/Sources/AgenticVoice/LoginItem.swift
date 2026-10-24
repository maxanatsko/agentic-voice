import ServiceManagement
import SwiftUI

/// Launch at login, via the system's login items.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// The Launch at Login toggle, for the menu and onboarding, with the reason it couldn't change.
struct LaunchAtLoginToggle: View {
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var error: String?

    var body: some View {
        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, enabled in
                // Resetting the toggle after a failure lands here too; there is nothing to change then.
                guard enabled != LoginItem.isEnabled else { return }
                do {
                    try LoginItem.set(enabled)
                    error = nil
                } catch {
                    self.error = "Launch at login: \(error.localizedDescription)"
                    launchAtLogin = LoginItem.isEnabled
                }
            }
        if let error {
            Text(error)
        }
    }
}
