import AppKit

/// The speaking overlay's settings, in the app's own defaults: the agentic-voice command
/// always announces speech, and only the app decides whether and how to show it.
@MainActor
enum OverlaySettings {
    nonisolated static let enabledKey = "overlay.enabled"
    nonisolated static let showOrbKey = "overlay.showOrb"
    nonisolated static let showTextKey = "overlay.showText"
    nonisolated static let styleKey = "overlay.style"
    nonisolated static let cornerKey = "overlay.corner"
    nonisolated static let displayKey = "overlay.display"
    /// Prefix of the dragged positions, one per display.
    nonisolated static let positionKeyPrefix = "overlay.position."

    private static var defaults: UserDefaults { .standard }

    static var enabled: Bool { defaults.object(forKey: enabledKey) as? Bool ?? true }
    static var showOrb: Bool { defaults.object(forKey: showOrbKey) as? Bool ?? true }
    static var showText: Bool { defaults.object(forKey: showTextKey) as? Bool ?? true }
    static var style: OverlayStyle { defaults.string(forKey: styleKey).flatMap { OverlayStyle(rawValue: $0) } ?? .floating }
    static var corner: OverlayCorner { defaults.string(forKey: cornerKey).flatMap { OverlayCorner(rawValue: $0) } ?? .bottomRight }
    static var display: OverlayDisplay { defaults.string(forKey: displayKey).flatMap { OverlayDisplay(rawValue: $0) } ?? .pointer }

    /// Where the companion was dragged to on `screen`: the bottom corner on its orb's side, relative
    /// to the screen's origin so it survives rearranging displays.
    static func draggedAnchor(on screen: NSScreen) -> CGPoint? {
        guard let pair = defaults.array(forKey: positionKey(screen)) as? [Double], pair.count == 2 else { return nil }
        return CGPoint(x: screen.frame.minX + pair[0], y: screen.frame.minY + pair[1])
    }

    static func saveDraggedAnchor(_ point: CGPoint, on screen: NSScreen) {
        defaults.set([Double(point.x - screen.frame.minX), Double(point.y - screen.frame.minY)], forKey: positionKey(screen))
    }

    static func forgetDraggedPosition(on screen: NSScreen) {
        defaults.removeObject(forKey: positionKey(screen))
    }

    static func forgetDraggedPositions() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(positionKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Per display, not per model: two identical monitors share a name but not a display ID.
    private static func positionKey(_ screen: NSScreen) -> String {
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        return positionKeyPrefix + (id.map(String.init) ?? screen.localizedName)
    }
}

enum OverlayStyle: String, CaseIterable, Identifiable {
    /// The orb floats on its own, in a corner or wherever it was dragged, and what it says rises
    /// above it in bubbles.
    case floating
    /// A cream island grows down from the top centre of any display, around the notch if there is one.
    case notch

    var id: Self { self }

    var title: String {
        switch self {
        case .floating: return "Companion"
        case .notch: return "Island"
        }
    }
}

enum OverlayCorner: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: Self { self }

    var title: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

enum OverlayDisplay: String, CaseIterable, Identifiable {
    /// The display under the pointer when speech starts.
    case pointer
    /// The display with the menu bar.
    case main

    var id: Self { self }

    var title: String {
        switch self {
        case .pointer: return "Display with the Pointer"
        case .main: return "Main Display"
        }
    }

    @MainActor var screen: NSScreen? {
        switch self {
        case .pointer:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.screens.first
        case .main:
            return NSScreen.screens.first
        }
    }
}

@MainActor
extension NSScreen {
    /// The menu bar's height, which the island hangs through: taller on displays with a notch.
    var menuBarHeight: CGFloat {
        max(safeAreaInsets.top, frame.maxY - visibleFrame.maxY, NSStatusBar.system.thickness)
    }

    /// The camera housing, in screen coordinates; nil on displays without one. It is what the
    /// menu bar areas on either side of it leave of the screen's width.
    var notchFrame: CGRect? {
        guard safeAreaInsets.top > 0, let left = auxiliaryTopLeftArea?.width, let right = auxiliaryTopRightArea?.width else { return nil }
        return CGRect(x: frame.minX + left, y: frame.maxY - safeAreaInsets.top,
                      width: frame.width - left - right, height: safeAreaInsets.top)
    }
}
