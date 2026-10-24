import ServiceManagement
import SwiftUI

/// Launch at login, via the system's login items.
enum LoginItem {
    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// The login item's state, shared by every Launch at Login toggle so they always agree.
@MainActor
final class LoginItemState: ObservableObject {
    static let shared = LoginItemState()

    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var error: String?

    var isOn: Bool { status == .enabled || status == .requiresApproval }

    func set(_ enabled: Bool) {
        do {
            try LoginItem.set(enabled)
            error = nil
        } catch {
            self.error = "Launch at login: \(error.localizedDescription)"
        }
        refresh()
    }

    /// Picks up changes made elsewhere, such as in System Settings.
    func refresh() {
        status = SMAppService.mainApp.status
    }
}

/// The Launch at Login toggle, for the menu and onboarding, with the reason it isn't on.
struct LaunchAtLoginToggle: View {
    @ObservedObject private var state = LoginItemState.shared

    var body: some View {
        Toggle("Launch at Login", isOn: Binding(get: { state.isOn }, set: { state.set($0) }))
            .onAppear { state.refresh() }
        if let error = state.error {
            Text(error)
        } else if state.status == .requiresApproval {
            Text("Approve Agentic Voice in System Settings → General → Login Items.")
        }
    }
}
