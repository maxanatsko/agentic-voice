import AgenticVoiceKit
import AppKit
import OrbKit
import SwiftUI

/// The overlay panel's content: the companion or the island, for the current utterance.
struct OverlayView: View {
    @ObservedObject var overlay: SpeechOverlay
    /// Lays out the open state whatever `expanded` says, to measure the panel.
    var measuring = false

    var body: some View {
        if let presentation = overlay.presentation {
            let open = measuring || overlay.expanded
            switch presentation.style {
            case .floating: Companion(presentation: presentation, open: open, overlay: overlay)
            case .notch: IslandCard(presentation: presentation, open: open, overlay: overlay)
            }
        }
    }
}

/// The overlay's warm palette: cream paper and brown ink, dark brown and cream in Dark Mode.
enum Warm {
    static func paper(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.17, green: 0.13, blue: 0.12) : Color(red: 1, green: 0.98, blue: 0.96)
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.96, green: 0.91, blue: 0.88) : Color(red: 0.23, green: 0.16, blue: 0.13)
    }

    static let glow = Color(red: 0.91, green: 0.38, blue: 0.30)
    static let text = Font.system(.callout, design: .serif)

    /// The width `text` needs on one line in `Warm.text`, up to `limit`, where it wraps. The panel is
    /// measured without a width to offer, so the text's width has to be fixed before layout.
    static func width(of text: String, limit: CGFloat) -> CGFloat {
        let base = NSFont.preferredFont(forTextStyle: .callout)
        let font = base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: base.pointSize) } ?? base
        return min(limit, ceil((text as NSString).size(withAttributes: [.font: font]).width) + 2)
    }
}

/// The orb on its own, with a soft glow that breathes behind it.
struct GlowingOrb: View {
    let kind: SpeechKind?
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        ThinkingOrb(state: OrbState(kind: kind), displaySize: size)
            .background {
                Circle()
                    .fill(RadialGradient(colors: [Warm.glow.opacity(0.35), Warm.glow.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: size * 0.8))
                    .frame(width: size * 1.6, height: size * 1.6)
                    .scaleEffect(breathing ? 1.12 : 1)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { breathing = true }
            }
    }
}

/// The floating orb, with what it says in bubbles rising above it: the current line, and the
/// agent's previous two faded above it. Dragged anywhere; double-click puts it back in the corner.
struct Companion: View {
    let presentation: SpeechOverlay.Presentation
    let open: Bool
    let overlay: SpeechOverlay

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let alignment: HorizontalAlignment = presentation.trailing ? .trailing : .leading
        VStack(alignment: alignment, spacing: 8) {
            if presentation.showText {
                ForEach(Array(presentation.earlier.enumerated()), id: \.element.id) { index, line in
                    Bubble(utterance: line, trailing: presentation.trailing, current: false)
                        .opacity(index == presentation.earlier.count - 1 ? 0.75 : 0.5)
                }
                Bubble(utterance: presentation.utterance, trailing: presentation.trailing, current: true, overlay: overlay)
            }
            if presentation.showOrb {
                GlowingOrb(kind: presentation.utterance.kind, size: 48)
                    .frame(width: 64, height: 64)
            }
        }
        .gesture(WindowDragGesture())
        // Alongside the drag, which would otherwise take the clicks.
        .simultaneousGesture(TapGesture(count: 2).onEnded { overlay.resetPosition() })
        // Room for the bubbles' shadows and the close button, inside the panel.
        .padding(16)
        .opacity(open ? 1 : 0)
        .offset(y: open || reduceMotion ? 0 : 10)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4), value: open)
    }
}

/// One line the companion said, in a speech bubble whose tail corner points down at the orb.
/// The current one names the project and carries the close button.
struct Bubble: View {
    let utterance: Utterance
    let trailing: Bool
    let current: Bool
    var overlay: SpeechOverlay?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 16, bottomLeading: trailing ? 16 : 4,
                                                              bottomTrailing: trailing ? 4 : 16, topTrailing: 16),
                                           style: .continuous)
        VStack(alignment: .leading, spacing: 2) {
            if current, let project = utterance.project {
                Text(project).font(.caption.weight(.medium)).foregroundStyle(Warm.ink(colorScheme).opacity(0.55)).lineLimit(1)
            }
            // Agents speak a sentence or two; anything longer is cut short here.
            Text(utterance.text)
                .font(Warm.text)
                .foregroundStyle(Warm.ink(colorScheme))
                .lineLimit(current ? 6 : 2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Wide enough for the project name too, when it's longer than a short line.
        .frame(width: max(Warm.width(of: utterance.text, limit: 280),
                          current ? Warm.width(of: utterance.project ?? "", limit: 280) : 0), alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(Warm.paper(colorScheme), in: shape)
        .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
        .overlay(alignment: trailing ? .topLeading : .topTrailing) {
            if let overlay {
                Button { overlay.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Warm.paper(colorScheme), in: Circle())
                        .shadow(color: .black.opacity(0.12), radius: 3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Warm.ink(colorScheme).opacity(0.6))
                .offset(x: trailing ? -6 : 6, y: -6)
                .help("Hide until the next message")
            }
        }
    }
}

/// A cream island that grows down from the top centre of the display, through the menu bar and
/// around the notch if there is one, and shrinks back up and fades when the voice stops. Clicking it hides it.
struct IslandCard: View {
    let presentation: SpeechOverlay.Presentation
    let open: Bool
    let overlay: SpeechOverlay

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The concave corners where the island meets the top edge of the screen.
    private static let shoulder: CGFloat = 10
    /// Its width when closed, on a display without a notch to shrink into.
    private static let closedWidth: CGFloat = 180

    var body: some View {
        let island = presentation.island ?? .init(band: 24)
        let closedWidth = island.notch?.width ?? Self.closedWidth
        let shape = NotchShape(shoulder: Self.shoulder, radius: open ? 22 : 10)
        VStack(spacing: 0) {
            // Behind the menu bar and the camera housing.
            Color.clear.frame(height: island.band)
            HStack(spacing: 10) {
                if presentation.showOrb {
                    ThinkingOrb(state: OrbState(kind: presentation.utterance.kind), displaySize: 30)
                }
                if presentation.showText {
                    Text(presentation.utterance.text)
                        .font(Warm.text)
                        .foregroundStyle(Warm.ink(colorScheme))
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: Warm.width(of: presentation.utterance.text, limit: 380), alignment: .leading)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .fixedSize()
            .opacity(open ? 1 : 0)
        }
        .frame(minWidth: closedWidth, alignment: .top)
        // Closed, it is the size of the notch or a small tab, and the content beyond it is clipped away.
        .frame(width: open ? nil : closedWidth, height: open ? nil : island.band, alignment: .top)
        .padding(.horizontal, Self.shoulder)
        .background(shape.fill(Warm.paper(colorScheme)))
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { overlay.dismiss() }
        // Cream would not vanish into the black notch, so it fades as it closes, on any display.
        .opacity(open ? 1 : 0)
        .shadow(color: .black.opacity(open ? 0.15 : 0), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.82), value: open)
    }
}

/// The island's outline: flat along the top edge of the screen, concave shoulders into the menu
/// bar, straight sides and rounded bottom corners.
struct NotchShape: Shape {
    var shoulder: CGFloat
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let s = shoulder
        let r = max(0, min(radius, rect.height - s, (rect.width - 2 * s) / 2))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + s, y: rect.minY + s), control: CGPoint(x: rect.minX + s, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + s + r, y: rect.maxY), control: CGPoint(x: rect.minX + s, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - s - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - s, y: rect.maxY - r), control: CGPoint(x: rect.maxX - s, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - s, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
