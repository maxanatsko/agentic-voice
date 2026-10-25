import Foundation

/// Morphs one state's particles into another's, so a change of state looks alive rather than cut.
/// Not part of thinking-orbs: the library only ever draws one state at a time.
public enum OrbMorph {
    /// How much of the transition the per-dot start delays take up, so dots leave in a ripple.
    static let spread = 0.35
    /// How far a dot swings off its straight path at the middle of its flight, as a share of the canvas.
    static let swing = 0.045

    /// `from` and `to`, two frames at the same instant on a `size` canvas, blended by `progress`
    /// (0 = `from`, 1 = `to`). Dots are paired by their angle around the centre, so each one flies
    /// to the nearest place in the new shape; when one frame has more, the other's dots split to
    /// fill in. Each dot starts after its own short delay and arcs to one side on the way, and
    /// lines cross-fade.
    public static func blend(_ from: OrbFrame, _ to: OrbFrame, progress: Double, size: Double) -> OrbFrame {
        let p = min(1, max(0, progress))
        let lines = from.lines.map { faded($0, by: 1 - p) } + to.lines.map { faded($0, by: p) }
        if from.dots.isEmpty || to.dots.isEmpty {
            let dots = from.dots.map { faded($0, by: 1 - p) } + to.dots.map { faded($0, by: p) }
            return OrbFrame(dots: dots.sorted { $0.z < $1.z }, lines: lines)
        }
        let a = byAngle(from.dots, size), b = byAngle(to.dots, size)
        let n = max(a.count, b.count)
        // A dot standing in for several shares its ink among them, so the shape keeps its weight.
        let shareA = Double(a.count) / Double(n), shareB = Double(b.count) / Double(n)
        var dots: [OrbDot] = []
        dots.reserveCapacity(n)
        for i in 0..<n {
            let da = a[i * a.count / n], db = b[i * b.count / n]
            let delay = spread * OrbEngine.hashD(Double(i), 3.1)
            let x = min(1, max(0, (p - delay) / (1 - spread)))
            let q = x * x * (3 - 2 * x)
            // An arc to one side of the straight path, widest halfway.
            let dx = db.x - da.x, dy = db.y - da.y
            let len = max(1e-9, (dx * dx + dy * dy).squareRoot())
            let bend = sin(.pi * q) * swing * size * (OrbEngine.hashD(Double(i), 7.7) * 2 - 1)
            dots.append(OrbDot(
                x: OrbEngine.lerp(da.x, db.x, q) - dy / len * bend,
                y: OrbEngine.lerp(da.y, db.y, q) + dx / len * bend,
                z: OrbEngine.lerp(da.z, db.z, q),
                r: OrbEngine.lerp(da.r, db.r, q),
                white: OrbEngine.lerp(da.white, db.white, q),
                a: OrbEngine.lerp(da.a * shareA, db.a * shareB, q)))
        }
        return OrbFrame(dots: dots.sorted { $0.z < $1.z }, lines: lines)
    }

    /// The dots in order of their angle around the canvas centre.
    static func byAngle(_ dots: [OrbDot], _ size: Double) -> [OrbDot] {
        let c = size / 2
        return dots.map { (atan2($0.y - c, $0.x - c), $0) }.sorted { $0.0 < $1.0 }.map(\.1)
    }

    static func faded(_ d: OrbDot, by f: Double) -> OrbDot {
        var d = d
        d.a *= f
        return d
    }

    static func faded(_ l: OrbLine, by f: Double) -> OrbLine {
        var l = l
        l.a *= f
        return l
    }
}
