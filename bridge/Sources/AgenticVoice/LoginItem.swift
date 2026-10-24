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
/// It reads the system's state rather than caching it, so copies in both places agree.
struct LaunchAtLoginToggle: View {
    @State private var error: String?
    /// Bumped after each change, so this copy redraws with the system's state.
    @State private var changes = 0

    var body: some View {
        Toggle("Launch at Login", isOn: Binding(get: { LoginItem.isEnabled }, set: { enabled in
            do {
                try LoginItem.set(enabled)
                error = nil
            } catch {
                self.error = "Launch at login: \(error.localizedDescription)"
            }
            changes += 1
        }))
        .id(changes)
        if let error {
            Text(error)
        }
    }
}
