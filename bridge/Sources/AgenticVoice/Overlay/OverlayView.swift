import OrbKit
import SwiftUI

/// The overlay panel's content: the floating card or the grown notch, for the current utterance.
struct OverlayView: View {
    @ObservedObject var overlay: SpeechOverlay
    /// Lays out the open state whatever `expanded` says, to measure the panel.
    var measuring = false

    var body: some View {
        if let presentation = overlay.presentation {
            let open = measuring || overlay.expanded
            switch presentation.style {
            case .floating: FloatingCard(presentation: presentation, open: open, overlay: overlay)
            case .notch: NotchCard(presentation: presentation, open: open, overlay: overlay)
            }
        }
    }
}

/// The orb and the spoken text, each shown only when its setting is on.
struct OverlayContent: View {
    let presentation: SpeechOverlay.Presentation

    var body: some View {
        HStack(spacing: 12) {
            if presentation.showOrb {
                ThinkingOrb(state: OrbState(kind: presentation.utterance.kind), displaySize: 44)
            }
            if presentation.showText {
                VStack(alignment: .leading, spacing: 2) {
                    if let project = presentation.utterance.project {
                        Text(project).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    // Agents speak a sentence or two; anything longer is cut short here.
                    Text(presentation.utterance.text)
                        .font(.callout)
                        .lineLimit(5)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 280, alignment: .leading)
            }
        }
    }
}

/// A material card, dragged by its background; double-click puts it back in the default corner.
struct FloatingCard: View {
    let presentation: SpeechOverlay.Presentation
    let open: Bool
    let overlay: SpeechOverlay

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        OverlayContent(presentation: presentation)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Self.shape)
            .overlay(Self.shape.strokeBorder(.primary.opacity(0.08)))
            .overlay(alignment: .topTrailing) {
                Button { overlay.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .offset(x: 6, y: -6)
                .help("Hide until the next message")
            }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .gesture(WindowDragGesture())
            // Alongside the drag, which would otherwise take the clicks.
            .simultaneousGesture(TapGesture(count: 2).onEnded { overlay.resetPosition() })
            // Room for the shadow and the close button, inside the panel.
            .padding(16)
            .opacity(open ? 1 : 0)
            .scaleEffect(open || reduceMotion ? 1 : 0.94)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35), value: open)
    }
}

/// The notch, grown down and out to hold the orb and text; it shrinks back into the camera
/// housing when the voice stops. Clicking it hides it.
struct NotchCard: View {
    let presentation: SpeechOverlay.Presentation
    let open: Bool
    let overlay: SpeechOverlay

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The concave corners where the notch meets the menu bar.
    private static let shoulder: CGFloat = 8

    var body: some View {
        let notch = presentation.notch ?? .zero
        let shape = NotchShape(shoulder: Self.shoulder, radius: open ? 24 : 10)
        VStack(spacing: 0) {
            // Behind the camera housing.
            Color.clear.frame(height: notch.height)
            OverlayContent(presentation: presentation)
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 16)
                .fixedSize()
                .opacity(open ? 1 : 0)
        }
        .frame(minWidth: notch.width, alignment: .top)
        // Closed, it is the notch's size, and the content beyond it is clipped away.
        .frame(width: open ? nil : notch.width, height: open ? nil : notch.height, alignment: .top)
        .padding(.horizontal, Self.shoulder)
        .background(shape.fill(.black))
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { overlay.dismiss() }
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.82), value: open)
    }
}

/// The notch's outline: flat along the top edge of the screen, concave shoulders into the menu
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
