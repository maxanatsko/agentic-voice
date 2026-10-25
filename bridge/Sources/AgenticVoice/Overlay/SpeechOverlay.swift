import AgenticVoiceKit
import AppKit
import SwiftUI

/// Shows what agents are saying while they speak: listens for the speech events every
/// agentic-voice process posts and puts the orb and text in a floating card or the notch.
/// Only one session speaks at a time, so there is one overlay and no queue.
@MainActor
final class SpeechOverlay: ObservableObject {
    /// What the overlay shows, fixed when an utterance starts so a settings change never
    /// rearranges it mid-sentence.
    struct Presentation: Equatable {
        var utterance: Utterance
        var style: OverlayStyle
        var showOrb: Bool
        var showText: Bool
        /// The notch the overlay grows out of, in screen coordinates; nil for the floating card.
        var notch: CGRect?
    }

    @Published private(set) var presentation: Presentation?
    /// Drives the open and close animations; false while the panel fades in or out.
    @Published private(set) var expanded = false

    private var panel: OverlayPanel?
    private var observers: [NSObjectProtocol] = []
    private var hiding: Task<Void, Never>?
    /// Fires when the speaking process exits, in case it dies without saying it ended.
    private var exitWatch: DispatchSourceProcess?

    /// How long the text stays after the voice stops, then how long the close animation takes.
    private static let linger: Duration = .milliseconds(700)
    private static let closing: Duration = .milliseconds(450)

    func start() {
        guard observers.isEmpty else { return }
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: DistributedSpeechEvents.name, object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = DistributedSpeechEvents.decode(notification) else { return }
            MainActor.assumeIsolated { self?.handle(event) }
        })
        // Turning the overlay off, from the menu or Settings, closes one that is showing.
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.presentation != nil else { return }
                if !OverlaySettings.enabled || !(OverlaySettings.showOrb || OverlaySettings.showText) { self.dismiss() }
            }
        })
    }

    func handle(_ event: SpeechEvent) {
        switch event {
        case .started(let utterance):
            show(utterance)
        case .ended(let id):
            // Already closing, say because it was dismissed: let that finish.
            if presentation?.utterance.id == id, hiding == nil { hide() }
        }
    }

    /// Closes the overlay for the current utterance; the voice carries on.
    func dismiss() {
        hide(after: .zero)
    }

    /// Forgets where the card was dragged on its display and moves it back to the default corner.
    func resetPosition() {
        guard let panel, let screen = panel.screen, presentation?.style == .floating else { return }
        OverlaySettings.forgetDraggedPosition(on: screen)
        place(panel, on: screen)
    }

    private func show(_ utterance: Utterance) {
        let showOrb = OverlaySettings.showOrb, showText = OverlaySettings.showText
        guard OverlaySettings.enabled, showOrb || showText, let screen = OverlaySettings.display.screen else { return }
        hiding?.cancel()
        hiding = nil
        // The notch style needs a notch; elsewhere it falls back to the card.
        let notch = OverlaySettings.style == .notch ? screen.notchFrame : nil
        let next = Presentation(utterance: utterance, style: notch == nil ? .floating : .notch,
                                showOrb: showOrb, showText: showText, notch: notch)
        // A new layout starts closed so it opens with its own animation; the same layout just updates.
        let continuing = panel?.isVisible == true && expanded && presentation.map { Self.sameLayout($0, next) } == true
        if !continuing { expanded = false }
        presentation = next

        let panel = self.panel ?? makePanel()
        panel.isMovable = next.style == .floating
        place(panel, on: screen)
        panel.orderFrontRegardless()
        // Opened on the next pass, once the panel shows the closed state to animate from.
        if !continuing {
            Task { @MainActor in
                if self.presentation?.utterance.id == utterance.id { self.expanded = true }
            }
        }
        watchExit(of: utterance)
    }

    private func hide(after delay: Duration = linger) {
        exitWatch?.cancel()
        exitWatch = nil
        hiding?.cancel()
        hiding = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.expanded = false
            try? await Task.sleep(for: Self.closing)
            guard !Task.isCancelled else { return }
            self.panel?.orderOut(nil)
            self.presentation = nil
        }
    }

    private func watchExit(of utterance: Utterance) {
        exitWatch?.cancel()
        let source = DispatchSource.makeProcessSource(identifier: utterance.pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.handle(.ended(id: utterance.id)) }
        }
        source.resume()
        exitWatch = source
        // Exited before the source was armed: it never fires then.
        if kill(utterance.pid, 0) != 0 && errno == ESRCH { handle(.ended(id: utterance.id)) }
    }

    private static func sameLayout(_ a: Presentation, _ b: Presentation) -> Bool {
        a.style == b.style && a.showOrb == b.showOrb && a.showText == b.showText && a.notch == b.notch
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel()
        let hosting = NSHostingView(rootView: OverlayView(overlay: self))
        // The panel is sized from the measured content; the hosting view must not resize it.
        hosting.sizingOptions = []
        panel.contentView = hosting
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelMoved() }
        })
        self.panel = panel
        return panel
    }

    /// Sizes the panel to its content and puts it at the notch, the dragged position or the default corner.
    private func place(_ panel: OverlayPanel, on screen: NSScreen) {
        guard let presentation else { return }
        // Measured open, so the panel already has room for the open state while it animates there.
        let size = NSHostingView(rootView: OverlayView(overlay: self, measuring: true)).fittingSize
        let visible = screen.visibleFrame
        var origin: CGPoint
        if let notch = presentation.notch {
            origin = CGPoint(x: notch.midX - size.width / 2, y: screen.frame.maxY - size.height)
        } else if let topLeft = OverlaySettings.draggedTopLeft(on: screen) {
            origin = CGPoint(x: topLeft.x, y: topLeft.y - size.height)
        } else {
            let corner = OverlaySettings.corner
            let left = corner == .topLeft || corner == .bottomLeft
            let top = corner == .topLeft || corner == .topRight
            origin = CGPoint(x: left ? visible.minX : visible.maxX - size.width,
                             y: top ? visible.maxY - size.height : visible.minY)
        }
        if presentation.notch == nil {
            // Kept on screen, whatever the display arrangement was when it was dragged.
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    /// Saves the card's position after a drag. Only moves made with the mouse button down count,
    /// so placing the panel, or macOS moving it when displays change, never overrides the corner.
    private func panelMoved() {
        guard NSEvent.pressedMouseButtons & 1 != 0, let panel, let screen = panel.screen,
              presentation?.style == .floating else { return }
        OverlaySettings.saveDraggedTopLeft(CGPoint(x: panel.frame.minX, y: panel.frame.maxY), on: screen)
    }
}

/// A borderless panel above other windows, on every Space and over full-screen apps, that never
/// takes focus from the app you're working in.
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above the menu bar, so the notch style can cover it.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
