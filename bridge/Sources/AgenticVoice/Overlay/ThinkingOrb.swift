import AgenticVoiceKit
import AppKit
import OrbKit
import SwiftUI

/// A thinking-orbs (MIT, libraries.dev/orbs) animation, from visual-explainer's ThinkingOrb: the
/// geometry comes from `OrbEngine`, painted as matte dots in shades of the system accent color
/// with the library's tint ramp. The 64 pt tuning, drawn at `displaySize` with bolder dots and a
/// softer depth fade so it reads at that size. A change of state morphs the old particles into the
/// new shape (`OrbMorph`). Holds still under Reduce Motion, as the original does, and switches without morphing.
struct ThinkingOrb: View {
    var state: OrbState = .breathing
    var displaySize: CGFloat = 44

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The state being morphed away from, and when the morph began.
    @State private var morphFrom: OrbState?
    @State private var morphStart = Date.distantPast

    /// How far far-side dots fade toward the background (1 = the library's full fade).
    nonisolated private static let fade = 0.55
    nonisolated private static let morphDuration = 1.1

    /// The tuned preset with radii ×1.5 (the library's `dotSize` knob).
    @MainActor private static var cache: [OrbState: (speed: Double, opts: OrbOpts)] = [:]

    @MainActor private static func tuned(_ state: OrbState) -> (speed: Double, opts: OrbOpts) {
        if let hit = cache[state] { return hit }
        var p = OrbEngine.preset(state, .large)
        p.opts = OrbEngine.scaleRadii(p.opts, 1.5)
        cache[state] = p
        return p
    }

    var body: some View {
        let p = Self.tuned(state)
        let from = morphFrom.map { ($0, Self.tuned($0)) }
        let start = morphStart
        let dark = colorScheme == .dark
        let (r, g, b) = Self.inkRGB()
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            Canvas { gc, _ in
                // Reduce Motion paints the same fixed instant the library does.
                let now = ctx.date.timeIntervalSinceReferenceDate
                let size = OrbSize.large.rawValue
                var frame = OrbEngine.frame(state, size: Double(size), t: reduceMotion ? 0.6 : now * p.speed, opts: p.opts)
                // Each state keeps its own speed while the two blend.
                let progress = ctx.date.timeIntervalSince(start) / Self.morphDuration
                if let (old, op) = from, !reduceMotion, progress < 1 {
                    let previous = OrbEngine.frame(old, size: Double(size), t: now * op.speed, opts: op.opts)
                    frame = OrbMorph.blend(previous, frame, progress: progress, size: Double(size))
                }
                // The library's tint ramp, softened: far ink fades toward black on dark, toward white on light.
                func ink(_ white: Double, _ a: Double) -> Color {
                    let w = min(1, max(0, white)) * Self.fade
                    func ramp(_ c: Double) -> Double { dark ? c * (1 - w) : c + (1 - c) * w }
                    return Color(red: ramp(r), green: ramp(g), blue: ramp(b), opacity: a)
                }
                let scale = displaySize / CGFloat(size)
                gc.scaleBy(x: scale, y: scale)
                for l in frame.lines {
                    gc.stroke(Path { $0.move(to: CGPoint(x: l.x1, y: l.y1)); $0.addLine(to: CGPoint(x: l.x2, y: l.y2)) },
                              with: .color(ink(l.white, l.a)), lineWidth: l.w)
                }
                for d in frame.dots {
                    gc.fill(Path(ellipseIn: CGRect(x: d.x - d.r, y: d.y - d.r, width: d.r * 2, height: d.r * 2)),
                            with: .color(ink(d.white, d.a)))
                }
            }
        }
        .frame(width: displaySize, height: displaySize)
        .onChange(of: state) { old, _ in
            morphFrom = old
            morphStart = .now
        }
        .accessibilityHidden(true)
    }

    /// The system accent color, or the overlay's warm coral when the accent is a grey (Graphite):
    /// a mid grey faded toward the paper's own shade barely shows.
    private static func inkRGB() -> (Double, Double, Double) {
        var c = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        if c.saturationComponent < 0.15 { c = NSColor(srgbRed: 0.91, green: 0.38, blue: 0.30, alpha: 1) }
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }
}

extension OrbState {
    /// The orb for a speak tool kind: a flowing band for a summary, a waveform when it's your
    /// turn, scrambling bands for an alert, and a calm ring otherwise.
    init(kind: SpeechKind?) {
        switch kind {
        case .completion: self = .composing
        case .question: self = .listening
        case .alert: self = .solving
        case .custom, nil: self = .breathing
        }
    }
}
