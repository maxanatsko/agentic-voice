import Foundation

// Geometry of thinking-orbs (MIT, libraries.dev/orbs): pure math over (size, t, opts) that
// returns the dots and lines to paint, already z-sorted. A straight port of the library's
// engine, so `OrbEngineTests` can compare it number for number with the JavaScript.

/// The nine animated states.
public enum OrbState: String, CaseIterable, Sendable {
    /// Particles on tilted orbits.
    case working
    /// A scan meridian sweeps a dotted globe.
    case searching
    /// Bands scramble in quarter turns, then click back.
    case solving
    /// A waveform rolls through latitude rings.
    case listening
    /// A constellation wires itself, packets running the edges.
    case connecting
    /// Three strands plait around the sphere.
    case weaving
    /// An undulating multi-band sash.
    case composing
    /// A face-on ring slowly morphing.
    case breathing
    /// A dotted outline morphs circle → triangle → square.
    case shaping
}

/// The two hand-tuned sizes: 64 (chat-avatar scale) and 20 (inline-text scale).
public enum OrbSize: Int, Sendable { case large = 64, small = 20 }

public typealias OrbOpts = [String: Double]

public struct OrbDot: Equatable, Sendable {
    public var x, y, z, r: Double
    /// Ink value: 0 = darkest ink on paper. Mirrored on dark themes.
    public var white: Double
    public var a: Double
}

public struct OrbLine: Equatable, Sendable {
    public var x1, y1, x2, y2: Double
    public var white, a, w: Double
}

public struct OrbFrame: Sendable {
    /// Far to near: the order to draw in.
    public var dots: [OrbDot]
    /// Drawn before the dots.
    public var lines: [OrbLine]
}

public enum OrbEngine {
    /// Draw options and animation speed for a state at a tuned size.
    public static func preset(_ state: OrbState, _ size: OrbSize) -> (speed: Double, opts: OrbOpts) {
        let mode = mode(state)
        let p = presets[mode]![size]!
        var o = baseProfiles[mode]!
        if p.count != 1 { o = scaleCounts(o, p.count) }
        if p.size != 1 { o = scaleRadii(o, p.size) }
        o.merge(p.extra) { $1 }
        return (p.speed, o)
    }

    /// The frame for `state` at canvas size `size` (points) and animation time `t`.
    public static func frame(_ state: OrbState, size: Double, t: Double, opts: OrbOpts) -> OrbFrame {
        switch mode(state) {
        case "orbits": return orbits(size, t, opts)
        case "globe": return globe(size, t, opts)
        case "rubik": return rubik(size, t, opts)
        case "wave": return wave(size, t, opts)
        case "web": return web(size, t, opts)
        case "braid": return braid(size, t, opts)
        case "morph": return morph(size, t, opts)
        default: return ribbon(size, t, opts)  // ribbon and ring
        }
    }

    static func mode(_ s: OrbState) -> String {
        switch s {
        case .working: "orbits"
        case .searching: "globe"
        case .solving: "rubik"
        case .listening: "wave"
        case .connecting: "web"
        case .weaving: "braid"
        case .composing: "ribbon"
        case .breathing: "ring"
        case .shaping: "morph"
        }
    }

    // MARK: Profiles

    static let baseProfiles: [String: OrbOpts] = [
        "globe": ["latRings": 17, "lonDensity": 44, "rBase": 0.6, "rDepth": 1.7, "rBoost": 1, "inkFar": 0.62,
                  "inkSpan": 0.54, "rsPow": 0.6, "rMin": 0.3],
        "orbits": ["orbitN": 12, "ghostN": 40, "ghostR": 0.9, "ghostA": 0.5, "particles": 3, "partR": 1.2,
                   "partRDepth": 1.6, "rsPow": 0.6, "rMin": 0.3],
        "rubik": ["latRings": 15, "lonDensity": 40, "moveCount": 14, "rBase": 0.6, "rDepth": 1.7, "rActive": 0.3,
                  "inkFar": 0.62, "inkSpan": 0.54, "rsPow": 0.6, "rMin": 0.3],
        "wave": ["rings": 15, "lonDensity": 40, "rBase": 0.6, "rDepth": 1.7, "rsPow": 0.6, "rMin": 0.3],
        "web": ["nodeN": 30, "thr": 0.72, "signals": 5, "nodeR": 1.4, "nodeRDepth": 1.8, "lineW": 0.8, "rsPow": 0.6,
                "rMin": 0.3],
        "braid": ["strandN": 52, "turns": 3, "ghostN": 150, "rBase": 1.2, "rDepth": 1.8, "rsPow": 0.6, "rMin": 0.3],
        "ribbon": ["lanes": 5, "segs": 88, "ghostN": 150, "rBase": 1.1, "rDepth": 1.7, "rsPow": 0.6, "rMin": 0.3],
        // ring shares ribbon's painter; faceOn cancels the camera tilt and moves the undulation onto
        // the radius, and there is no ghost sphere behind it
        "ring": ["lanes": 5, "segs": 88, "ghostN": 0, "faceOn": 1, "rBase": 1.1, "rDepth": 1.7, "rsPow": 0.6,
                 "rMin": 0.3],
        "morph": ["rDot": 0.021, "iconD": 1, "rMin": 0.25],
    ]

    private struct Preset { var speed, count, size: Double; var extra: OrbOpts = [:] }

    private static let presets: [String: [OrbSize: Preset]] = [
        "orbits": [.large: Preset(speed: 1.885, count: 1, size: 1), .small: Preset(speed: 3.9, count: 0.238, size: 2.4)],
        "globe": [.large: Preset(speed: 2.015, count: 0.42, size: 1.15, extra: ["scanMul": 4.08, "dimBase": 0.45]),
                  .small: Preset(speed: 2.665, count: 0.105, size: 1.75, extra: ["scanMul": 4.335, "dimBase": 0.45])],
        "rubik": [.large: Preset(speed: 1.82, count: 0.35, size: 1.05), .small: Preset(speed: 1.95, count: 0.088, size: 1.9)],
        "wave": [.large: Preset(speed: 4.388, count: 0.341, size: 1), .small: Preset(speed: 3.998, count: 0.105, size: 1.6)],
        "web": [.large: Preset(speed: 3.315, count: 1.35, size: 0.95), .small: Preset(speed: 6.63, count: 0.25, size: 1.52)],
        "braid": [.large: Preset(speed: 1.625, count: 0.5, size: 1), .small: Preset(speed: 2.75, count: 0.1125, size: 1.36)],
        "ribbon": [.large: Preset(speed: 2.34, count: 0.25, size: 0.85, extra: ["spin": 0, "bandMul": 3.9, "wobMul": 1]),
                   .small: Preset(speed: 3.12, count: 0.051, size: 1.073, extra: ["spin": 0, "bandMul": 4.94, "wobMul": 1])],
        "ring": [.large: Preset(speed: 3.24, count: 0.25, size: 0.956, extra: ["spin": 0, "bandMul": 3.627, "wobMul": 0.368]),
                 .small: Preset(speed: 3.78, count: 0.028, size: 1.622, extra: ["spin": 0, "bandMul": 3.968, "wobMul": 0.565])],
        "morph": [.large: Preset(speed: 2.405, count: 0.702, size: 0.395, extra: ["spread": 1.45]),
                  .small: Preset(speed: 2.08, count: 0.53, size: 1.011, extra: ["spread": 1.45])],
    ]

    private static let countPairs = [("latRings", "lonDensity"), ("rings", "lonDensity"), ("lanes", "segs")]
    private static let countKeys = ["orbitN", "ghostN", "nodeN", "strandN", "signals"]
    private static let radiusKeys = ["rBase", "rDepth", "rActive", "rDot", "ghostR", "partR", "partRDepth", "nodeR",
                                     "nodeRDepth"]

    /// Scales every dot count, keeping grid pairs (rings × density) in proportion.
    public static func scaleCounts(_ opts: OrbOpts, _ scale: Double) -> OrbOpts {
        var out = opts
        var done = Set<String>()
        let rt = scale.squareRoot()
        for (a, b) in countPairs {
            if let va = out[a], let vb = out[b], !done.contains(a), !done.contains(b) {
                out[a] = max(2, jsRound(va * rt))
                out[b] = max(2, jsRound(vb * rt))
                done.insert(a)
                done.insert(b)
            }
        }
        for k in countKeys {
            if let v = out[k], v != 0, !done.contains(k) { out[k] = max(1, jsRound(v * scale)) }
        }
        if let v = out["iconD"] { out["iconD"] = max(0.02, v * scale) }
        return out
    }

    /// Scales every dot radius.
    public static func scaleRadii(_ opts: OrbOpts, _ scale: Double) -> OrbOpts {
        var out = opts
        for k in radiusKeys { if let v = out[k] { out[k] = v * scale } }
        out["rSizeMul"] = (out["rSizeMul"] ?? 1) * scale
        return out
    }

    // MARK: Core

    /// JavaScript's Math.round (halves round up).
    static func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

    static func frac(_ x: Double) -> Double { x - x.rounded(.down) }

    static func lerp(_ a: Double, _ b: Double, _ f: Double) -> Double { a + (b - a) * f }

    /// Deterministic hash in [0, 1).
    static func hashD(_ a: Double, _ b: Double) -> Double {
        let h = sin(a * 12.9898 + b * 78.233) * 43758.5453
        return h - h.rounded(.down)
    }

    /// Value noise on a 2D lattice.
    static func vnoise(_ x: Double, _ y: Double) -> Double {
        let xi = x.rounded(.down), yi = y.rounded(.down)
        var fx = x - xi, fy = y - yi
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        let a = hashD(xi, yi), b = hashD(xi + 1, yi), c = hashD(xi, yi + 1), d = hashD(xi + 1, yi + 1)
        return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy
    }

    /// Stable directions on a unit sphere (Fibonacci lattice).
    static func fibDir(_ i: Int, _ n: Int) -> (Double, Double, Double) {
        let golden = Double.pi * (3 - 5.0.squareRoot())
        let y = 1 - 2 * (Double(i) + 0.5) / Double(n)
        let rad = (1 - y * y).squareRoot()
        let a = Double(i) * golden
        return (rad * cos(a), y, rad * sin(a))
    }

    /// Shortest signed angular distance, wrapped to (-π, π].
    static func angleDelta(_ a: Double, _ b: Double) -> Double { atan2(sin(a - b), cos(a - b)) }

    /// Spin + tilt + orthographic projection.
    static func makeProj(_ yaw: Double, _ tilt: Double, _ cx: Double, _ cy: Double, _ scale: Double)
        -> (Double, Double, Double) -> (Double, Double, Double) {
        let st = sin(tilt), ct = cos(tilt), sy = sin(yaw), cyw = cos(yaw)
        return { x, y, z in
            let x1 = x * cyw + z * sy
            let z1 = -x * sy + z * cyw
            let y1 = y * ct - z1 * st
            let z2 = y * st + z1 * ct
            return (cx + x1 * scale, cy - y1 * scale, z2)
        }
    }

    /// Dot radii were tuned for a 300 pt frame; sub-linear scaling keeps small spinners legible.
    static func radiusScale(_ size: Double, _ pow: Double) -> Double { Foundation.pow(size / 300, pow) }

    /// Drops invisible marks, clamps radii and sorts far to near (stable, like JS's sort).
    static func finalize(_ dots: [OrbDot], _ lines: [OrbLine], _ rMin: Double?) -> OrbFrame {
        let floor = rMin ?? 0.3
        let visible = dots.enumerated()
            .filter { $0.element.a >= 0.02 }
            .map { (i, d) -> (Int, OrbDot) in var d = d; d.r = max(floor, d.r); return (i, d) }
            .sorted { $0.1.z != $1.1.z ? $0.1.z < $1.1.z : $0.0 < $1.0 }
            .map(\.1)
        return OrbFrame(dots: visible, lines: lines.filter { $0.a >= 0.02 })
    }

    private static func int(_ o: OrbOpts, _ k: String, _ d: Double) -> Int { Int(o[k] ?? d) }

    // MARK: Modes

    static func orbits(_ size: Double, _ t: Double, _ o: OrbOpts) -> OrbFrame {
        // Options read once, outside the per-dot loops.
        let ghostA = o["ghostA"] ?? 0.5, ghostR = o["ghostR"] ?? 0.9, partR = o["partR"] ?? 1.2, partRDepth = o["partRDepth"] ?? 1.6
        let c = size / 2
        let R = size / 2 * 0.82
        let pt = makeProj(t * 0.12, 0.3, c, c, 1)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        var dots: [OrbDot] = []
        let orbitN = int(o, "orbitN", 12), ghostN = int(o, "ghostN", 40), particles = int(o, "particles", 3)
        for orb in 0..<orbitN {
            let ob = Double(orb)
            let h1 = hashD(ob, 1.7), h2 = hashD(ob, 5.2), h3 = hashD(ob, 8.9)
            let ro = R * (0.45 + 0.52 * h1)
            let th = h1 * 2 * .pi, phi = acos(2 * h2 - 1)
            let nx = sin(phi) * cos(th), ny = cos(phi), nz = sin(phi) * sin(th)
            var ux = -ny, uy = nx
            let uz = 0.0
            let ul = max(1e-6, (ux * ux + uy * uy).squareRoot())
            ux /= ul
            uy /= ul
            let vx = ny * uz - nz * uy, vy = nz * ux - nx * uz, vz = nx * uy - ny * ux
            let speed = (0.25 + 0.55 * h3) * (h3 > 0.5 ? 1 : -1)
            func point(_ a: Double) -> (Double, Double, Double) {
                pt((ux * cos(a) + vx * sin(a)) * ro, (uy * cos(a) + vy * sin(a)) * ro, (uz * cos(a) + vz * sin(a)) * ro)
            }
            for k in 0..<ghostN {
                let (px, py, z) = point(Double(k) / Double(ghostN) * 2 * .pi)
                let depth = (z / ro + 1) / 2
                dots.append(OrbDot(x: px, y: py, z: z, r: ghostR * rs, white: 0.72,
                                   a: ghostA * (0.4 + 0.6 * depth)))
            }
            for m in 0..<particles {
                let (px, py, z) = point(t * speed + Double(m) / Double(particles) * 2 * .pi + h2 * 6)
                let depth = (z / ro + 1) / 2
                dots.append(OrbDot(x: px, y: py, z: z, r: (partR + partRDepth * depth) * rs,
                                   white: 0.3 - 0.22 * depth, a: 1))
            }
        }
        return finalize(dots, [], o["rMin"])
    }

    static func globe(_ size: Double, _ t: Double, _ o: OrbOpts) -> OrbFrame {
        // Options read once, outside the per-dot loops.
        let dimBase = o["dimBase"] ?? 1, inkFar = o["inkFar"] ?? 0.62, inkSpan = o["inkSpan"] ?? 0.54, lonDensity = o["lonDensity"] ?? 44, rBase = o["rBase"] ?? 0.6, rBoost = o["rBoost"] ?? 1, rDepth = o["rDepth"] ?? 1.7, scanMul = o["scanMul"] ?? 1
        let spin = 0.5
        let c = size / 2
        let radius = size / 2 * 0.82
        let tilt = 0.4 + 0.06 * sin(t * 0.35)
        let pt = makeProj(t * spin, tilt, c, c, radius)
        let scan = t * (spin + (1.7 - spin) * scanMul)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        var dots: [OrbDot] = []
        let latRings = int(o, "latRings", 17)
        for li in 0...latRings {
            let lat = -Double.pi / 2 + Double(li) / Double(latRings) * .pi
            let cosLat = cos(lat), sinLat = sin(lat)
            let lonCount = max(1, Int(jsRound(abs(cosLat) * lonDensity)))
            for lj in 0..<lonCount {
                let lon = Double(lj) / Double(lonCount) * 2 * .pi
                let (px, py, z) = pt(cosLat * cos(lon), sinLat, cosLat * sin(lon))
                let depth = (z + 1) / 2
                let d = angleDelta(lon + t * spin, scan)
                let boost = exp(-(d * d) / 0.18) * max(0, z)
                dots.append(OrbDot(
                    x: px, y: py, z: z,
                    r: (rBase + rDepth * depth + rBoost * boost) * rs,
                    white: inkFar - inkSpan * depth,
                    // dimBase < 1 fades un-scanned dots so the meridian reads clearly
                    a: dimBase + (1 - dimBase) * min(1, boost)))
            }
        }
        return finalize(dots, [], o["rMin"])
    }

    private struct Move { var axis: Int; var lo, hi, ang: Double }

    private static func makeMoves(_ count: Int) -> [Move] {
        (0..<count).map { i in
            let d = Double(i)
            let axis = min(2, Int((hashD(d, 2.3) * 3).rounded(.down)))
            let lo = -1 + 0.5 * min(3, (hashD(d, 5.9) * 4).rounded(.down))
            let dir: Double = hashD(d, 7.7) < 0.5 ? 1 : -1
            return Move(axis: axis, lo: lo, hi: lo + 0.5, ang: dir * .pi / 2)
        }
    }

    /// How far each move has turned at `time`: scramble one by one, then unwind, then rest.
    private static func solveCycle(_ time: Double, _ count: Int, _ slotDur: Double, _ rest: Double)
        -> (amount: [Double], active: Int) {
        let cyc = 2 * Double(count) * slotDur + rest
        let tc = time.truncatingRemainder(dividingBy: cyc)
        var amount = [Double](repeating: 0, count: count)
        var active = -1
        if tc < 2 * Double(count) * slotDur {
            let slot = Int((tc / slotDur).rounded(.down))
            let p = (tc - Double(slot) * slotDur) / slotDur
            let cl = min(1, p / 0.7)
            let ep = 1 - pow(1 - cl, 3)
            if slot < count {
                for i in 0..<slot { amount[i] = 1 }
                amount[slot] = ep
                active = slot
            } else {
                let u = 2 * count - 1 - slot
                for i in 0..<u { amount[i] = 1 }
                amount[u] = 1 - ep
                active = u
            }
        }
        return (amount, active)
    }

    private static func applyMoves(_ p: (Double, Double, Double), _ moves: [Move], _ sc: (amount: [Double], active: Int))
        -> (Double, Double, Double, Bool) {
        var (x, y, z) = p
        var inActive = false
        for (i, mv) in moves.enumerated() {
            if sc.amount[i] <= 0 { continue }
            let coord = mv.axis == 0 ? x : mv.axis == 1 ? y : z
            if coord < mv.lo || coord >= mv.hi { continue }
            if i == sc.active { inActive = true }
            let a = mv.ang * sc.amount[i]
            let ca = cos(a), sa = sin(a)
            if mv.axis == 0 {
                let y2 = y * ca - z * sa
                z = y * sa + z * ca
                y = y2
            } else if mv.axis == 1 {
                let x2 = x * ca + z * sa
                z = -x * sa + z * ca
                x = x2
            } else {
                let x2 = x * ca - y * sa
                y = x * sa + y * ca
                x = x2
            }
        }
        return (x, y, z, inActive)
    }

    static func rubik(_ size: Double, _ t: Double, _ o: OrbOpts) -> OrbFrame {
        // Options read once, outside the per-dot loops.
        let inkFar = o["inkFar"] ?? 0.62, inkSpan = o["inkSpan"] ?? 0.54, lonDensity = o["lonDensity"] ?? 40, rActive = o["rActive"] ?? 0.3, rBase = o["rBase"] ?? 0.6, rDepth = o["rDepth"] ?? 1.7
        let c = size / 2
        let R = size / 2 * 0.82
        let pt = makeProj(t * 0.55, 0.35 + 0.1 * sin(t * 0.9), c, c, R)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        let moveCount = int(o, "moveCount", 14)
        let moves = makeMoves(moveCount)
        let sc = solveCycle(t, moveCount, 0.42, 1.2)
        var dots: [OrbDot] = []
        let latRings = int(o, "latRings", 15)
        for li in 0...latRings {
            let lat = -Double.pi / 2 + Double(li) / Double(latRings) * .pi
            let cosLat = cos(lat), sinLat = sin(lat)
            let lonCount = max(1, Int(jsRound(abs(cosLat) * lonDensity)))
            for lj in 0..<lonCount {
                let lon = Double(lj) / Double(lonCount) * 2 * .pi
                let (x, y, z, inActive) = applyMoves((cosLat * cos(lon), sinLat, cosLat * sin(lon)), moves, sc)
                let (px, py, zr) = pt(x, y, z)
                let depth = (zr + 1) / 2
                dots.append(OrbDot(
                    x: px, y: py, z: zr,
                    r: (rBase + rDepth * depth + (inActive ? rActive : 0)) * rs,
                    white: inkFar - inkSpan * depth - (inActive ? 0.14 : 0), a: 1))
            }
        }
        return finalize(dots, [], o["rMin"])
    }

    static func wave(_ size: Double, _ t: Double, _ o: OrbOpts) -> OrbFrame {
        // Options read once, outside the per-dot loops.
        let lonDensity = o["lonDensity"] ?? 40, rBase = o["rBase"] ?? 0.6, rDepth = o["rDepth"] ?? 1.7
        let c = size / 2
        let R = size / 2 * 0.874
        let pt = makeProj(t * 0.18, 0.38, c, c, 1)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        var dots: [OrbDot] = []
        let rings = int(o, "rings", 15)
        for ri in 0...rings {
            let r = Double(ri)
            let lat = -Double.pi / 2 + r / Double(rings) * .pi
            let cosLat = cos(lat), sinLat = sin(lat)
            let w = 0.62 * sin(t * 2.1 - r * 0.52) + 0.38 * sin(t * 1.27 + r * 0.83)
            let rr = R * (0.88 + 0.105 * w)
            let lonCount = max(1, Int(jsRound(abs(cosLat) * lonDensity)))
            for lj in 0..<lonCount {
                let lon = Double(lj) / Double(lonCount) * 2 * .pi
                let (px, py, z) = pt(cosLat * cos(lon) * rr, sinLat * rr, cosLat * sin(lon) * rr)
                let depth = (z / R + 1) / 2
                let crest = max(0, w)
                dots.append(OrbDot(
                    x: px, y: py, z: z,
                    r: (rBase + rDepth * depth) * (1 + 0.4 * crest) * rs,
                    white: 0.66 - 0.56 * depth - 0.1 * crest, a: 1))
            }
        }
        return finalize(dots, [], o["rMin"])
    }

    static func web(_ size: Double, _ t: Double, _ o: OrbOpts) -> OrbFrame {
        // Options read once, outside the per-dot loops.
        let lineW = o["lineW"] ?? 0.8, nodeR = o["nodeR"] ?? 1.4, nodeRDepth = o["nodeRDepth"] ?? 1.8, spread = o["spread"] ?? 1, thr = o["thr"] ?? 0.72
        let c = size / 2
        let R = size / 2 * 0.8 * spread
        let pt = makeProj(t * 0.12, 0.32, c, c, R)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        let nodeN = int(o, "nodeN", 30)
        var nodes: [(Double, Double, Double)] = []
        for i in 0..<nodeN {
            let d = fibDir(i, nodeN)
            let n = Double(i)
            let x = d.0 + 0.3 * (vnoise(n * 0.31 + 9, t * 0.24) - 0.5) * 2
            let y = d.1 + 0.3 * (vnoise(n * 0.53 + 27, t * 0.21) - 0.5) * 2
            let z = d.2 + 0.3 * (vnoise(n * 0.77 + 55, t * 0.27) - 0.5) * 2
            let l = (x * x + y * y + z * z).squareRoot()
            nodes.append((x / l, y / l, z / l))
        }
        var lines: [OrbLine] = []
        var dots: [OrbDot] = []
        for i in 0..<nodeN {
            for j in (i + 1)..<max(i + 1, nodeN) {
                let dx = nodes[i].0 - nodes[j].0, dy = nodes[i].1 - nodes[j].1, dz = nodes[i].2 - nodes[j].2
                let dist = (dx * dx + dy * dy + dz * dz).squareRoot()
                if dist >= thr { continue }
                let (x1, y1, z1) = pt(nodes[i].0, nodes[i].1, nodes[i].2)
                let (x2, y2, z2) = pt(nodes[j].0, nodes[j].1, nodes[j].2)
                let depth = ((z1 + z2) / 2 + 1) / 2
                lines.append(OrbLine(x1: x1, y1: y1, x2: x2, y2: y2, white: 0.42,
                                     a: (1 - dist / thr) * (0.3 + 0.55 * depth),
                                     w: max(0.6, lineW * rs)))
            }
        }
        for i in 0..<nodeN {
            let (px, py, z) = pt(nodes[i].0, nodes[i].1, nodes[i].2)
            let depth = (z + 1) / 2
            let pulse = 1 + 0.25 * sin(t * 1.4 + Double(i) * 2.7)
            dots.append(OrbDot(x: px, y: py, z: z, r: (nodeR + nodeRDepth * depth) * pulse * rs,
                               white: 0.55 - 0.45 * depth, a: 1))
        }
        let signals = int(o, "signals", 5)
        for s in 0..<signals {
            let sd = Double(s)
            let seg = (t * 0.55 + sd * 7.31).rounded(.down)
            let a = Int((hashD(seg, sd * 3.1 + 1.7) * Double(nodeN)).rounded(.down))
            let b = Int((hashD(seg, sd * 5.7 + 4.2) * Double(nodeN)).rounded(.down))
            if a == b { continue }
            let f = frac(t * 0.55 + sd * 7.31)
            let x = lerp(nodes[a].0, nodes[b].0, f), y = lerp(nodes[a].1, nodes[b].1, f), z = lerp(nodes[a].2, nodes[b].2, f)
            let l = max(1e-6, (x * x + y * y + z * z).squareRoot())
            let (px, py, zr) = pt(x / l, y / l, z / l)
            let depth = (zr + 1) / 2
            dots.append(OrbDot(x: px, y: py, z: zr, r: (nodeR * 1.5 + nodeRDepth * depth) * rs, white: 0.05,
                               a: 0.5 + 0.5 * depth))
        }
        return finalize(dots, lines, o["rMin"])
    }

    static func braid(_ size: Double, _ t: Double, _ o: OrbOpts) -> OrbFrame {
        // Options read once, outside the per-dot loops.
        let rBase = o["rBase"] ?? 1.2, rDepth = o["rDepth"] ?? 1.8, turns = o["turns"] ?? 3
        let c = size / 2
        let R = size / 2 * 0.76
        let pt = makeProj(t * 0.4, 0.3, c, c, 1)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        var dots: [OrbDot] = []
        let ghostN = int(o, "ghostN", 150)
        for i in 0..<ghostN {
            let d = fibDir(i, ghostN)
            let (px, py, z) = pt(d.0 * R, d.1 * R, d.2 * R)
            let depth = (z / R + 1) / 2
            dots.append(OrbDot(x: px, y: py, z: z, r: 0.8 * rs, white: 0.78, a: 0.1 + 0.22 * depth))
        }
        let strandN = int(o, "strandN", 52)
        for s in 0..<3 {
            let phase = Double(s) / 3 * 2 * .pi
            for i in 0..<strandN {
                let u = (frac(Double(i) / Double(strandN) + t * 0.045) * 2 - 1) * 0.96
                let surf = max(0, 1 - u * u).squareRoot()
                let endFade = min(1, (1 - abs(u)) / 0.1)
                let a = u * .pi * turns + phase
                let weave = 1 + 0.075 * sin(u * .pi * turns * 2 + phase * 2 + t * 0.8)
                let rr = surf * R * weave
                let (px, py, zr) = pt(cos(a) * rr, u * R * weave, sin(a) * rr)
                let depth = (zr / R + 1) / 2
                dots.append(OrbDot(x: px, y: py, z: zr, r: (rBase + rDepth * depth) * rs,
                                   white: 0.55 - 0.45 * depth, a: endFade * (0.45 + 0.55 * depth)))
            }
        }
        return finalize(dots, [], o["rMin"])
    }

    static func ribbon(_ size: Double, _ t: Double, _ o: OrbOpts) -> OrbFrame {
        // Options read once, outside the per-dot loops.
        let rBase = o["rBase"] ?? 1.1, rDepth = o["rDepth"] ?? 1.7, spin = o["spin"] ?? 1, wobMul = o["wobMul"] ?? 1
        let c = size / 2
        let R = size / 2 * 0.78
        let camTilt = 0.3
        let pt = makeProj(t * 0.1 * spin, camTilt, c, c, 1)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        var dots: [OrbDot] = []
        let ghostN = int(o, "ghostN", 150)
        for i in 0..<ghostN {
            let d = fibDir(i, ghostN)
            let (px, py, z) = pt(d.0 * R, d.1 * R, d.2 * R)
            let depth = (z / R + 1) / 2
            dots.append(OrbDot(x: px, y: py, z: z, r: 0.8 * rs, white: 0.78, a: 0.1 + 0.22 * depth))
        }
        let faceOn = (o["faceOn"] ?? 0) != 0
        let ya = t * 0.24 * spin
        let ta = faceOn ? -camTilt : 0.55 + 0.3 * sin(t * 0.18) * spin
        let ux = cos(ya), uy = 0.0, uz = sin(ya)
        let vx = -uz * sin(ta), vy = cos(ta), vz = ux * sin(ta)
        let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx
        let wobAmp = 0.23 * wobMul
        let baseR = faceOn ? R / (1 + 0.85 * wobAmp) : R
        let lanes = max(1, Int(jsRound((o["lanes"] ?? 5) * (o["bandMul"] ?? 1))))
        let segs = int(o, "segs", 88)
        for w in 0..<lanes {
            let wd = Double(w), mid = Double(lanes - 1) / 2
            let laneOff = (wd - mid) * 0.075
            let edge = abs(wd - mid) / max(1, mid)
            for k in 0..<segs {
                let a = Double(k) / Double(segs) * 2 * .pi
                let wob = (0.16 * sin(a * 3 - t * 1.7 + wd * 0.22) + 0.07 * sin(a * 5 + t * 1.1)) * wobMul
                let radial = faceOn ? 1 + wob : 1
                let off = faceOn ? laneOff : laneOff + wob
                let x = ux * cos(a) + vx * sin(a) + nx * off
                let y = uy * cos(a) + vy * sin(a) + ny * off
                let z = uz * cos(a) + vz * sin(a) + nz * off
                let l = (x * x + y * y + z * z).squareRoot()
                let rr = baseR * radial
                let (px, py, zr) = pt(x / l * rr, y / l * rr, z / l * rr)
                let depth = (zr / R + 1) / 2
                dots.append(OrbDot(
                    x: px, y: py, z: zr,
                    r: (rBase + rDepth * depth) * (1 - 0.25 * edge) * rs,
                    white: 0.52 - 0.44 * depth + 0.18 * edge, a: 0.4 + 0.6 * depth))
            }
        }
        return finalize(dots, [], o["rMin"])
    }

    // MARK: Morph

    private typealias Shape = @Sendable (Double) -> (Double, Double)

    private static func polyPath(_ verts: [(Double, Double)]) -> Shape {
        let v = verts.count
        var lens: [Double] = []
        var total = 0.0
        for i in 0..<v {
            let a = verts[i], b = verts[(i + 1) % v]
            let l = hypot(b.0 - a.0, b.1 - a.1)
            lens.append(l)
            total += l
        }
        return { [lens, total] f in
            var target = f * total
            var i = 0
            while target > lens[i] && i < v - 1 {
                target -= lens[i]
                i += 1
            }
            let a = verts[i], b = verts[(i + 1) % v]
            let ff = lens[i] != 0 ? min(1, target / lens[i]) : 0
            return (a.0 + (b.0 - a.0) * ff, a.1 + (b.1 - a.1) * ff)
        }
    }

    private static let cycle: [Shape] = [
        { f in let a = -Double.pi / 2 + f * 2 * .pi; return (cos(a) * 0.24, sin(a) * 0.24) },
        polyPath([(0, -0.26), (0.24, 0.16), (-0.24, 0.16)]),
        polyPath([(0, -0.2), (0.2, -0.2), (0.2, 0.2), (-0.2, 0.2), (-0.2, -0.2)]),
    ]

    static func morph(_ size: Double, _ t: Double, _ o: OrbOpts) -> OrbFrame {
        let hold = 1.4, morphDur = 0.9, seg = hold + morphDur
        let K = cycle.count
        let tc = t.truncatingRemainder(dividingBy: seg * Double(K))
        let shape = o["shape"]
        let held = shape.map { $0 >= 0 && $0 < Double(K) ? Int($0.rounded(.down)) : -1 } ?? -1
        let k = held >= 0 ? held : Int((tc / seg).rounded(.down))
        let local = held >= 0 ? t.truncatingRemainder(dividingBy: seg) : tc - Double(k) * seg
        let m: Double
        if held >= 0 || local <= hold { m = 0 } else { let x = (local - hold) / morphDur; m = x * x * (3 - 2 * x) }
        let sprd = o["spread"] ?? 1
        let pA = cycle[k]
        let pB = held >= 0 ? pA : cycle[(k + 1) % K]
        let M = 160
        let pts: [(Double, Double)] = (0..<M).map { i in
            let f = Double(i) / Double(M)
            let a = pA(f), b = pB(f)
            return ((a.0 + (b.0 - a.0) * m) * sprd, (a.1 + (b.1 - a.1) * m) * sprd)
        }
        var lens: [Double] = []
        var total = 0.0
        for i in 0..<M {
            let a = pts[i], b = pts[(i + 1) % M]
            let l = hypot(b.0 - a.0, b.1 - a.1)
            lens.append(l)
            total += l
        }
        let n = max(6, Int(jsRound(34 * (o["iconD"] ?? 1))))
        let re = (o["rDot"] ?? 0.021) * 1.35 * sprd
        let pulse = 1 + 0.02 * sin(local * 3.1)
        var dots: [OrbDot] = []
        let c2 = size / 2
        var sg = 0
        var acc = 0.0
        for k2 in 0..<n {
            let target = Double(k2) / Double(n) * total
            while acc + lens[sg] < target && sg < M - 1 {
                acc += lens[sg]
                sg += 1
            }
            let a = pts[sg], b = pts[(sg + 1) % M]
            let f = lens[sg] != 0 ? min(1, (target - acc) / lens[sg]) : 0
            let x = (a.0 + (b.0 - a.0) * f) * pulse
            let y = (a.1 + (b.1 - a.1) * f) * pulse
            dots.append(OrbDot(x: c2 + x * size, y: c2 + y * size, z: 0, r: max(0.35, re * size), white: 0.1, a: 1))
        }
        return finalize(dots, [], o["rMin"])
    }
}
