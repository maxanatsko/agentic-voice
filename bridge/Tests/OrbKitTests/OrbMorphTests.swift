import XCTest
@testable import OrbKit

/// The morph between two states starts exactly on the old shape and lands exactly on the new one.
final class OrbMorphTests: XCTestCase {
    private func frame(_ state: OrbState, t: Double = 1.3) -> OrbFrame {
        let p = OrbEngine.preset(state, .large)
        return OrbEngine.frame(state, size: 64, t: t, opts: p.opts)
    }

    private func positions(_ f: OrbFrame) -> Set<[Double]> {
        Set(f.dots.map { [($0.x * 1e6).rounded(), ($0.y * 1e6).rounded()] })
    }

    func testStartsOnTheOldShapeAndEndsOnTheNewOne() {
        let ring = frame(.breathing), wave = frame(.listening)
        let start = OrbMorph.blend(ring, wave, progress: 0, size: 64)
        let end = OrbMorph.blend(ring, wave, progress: 1, size: 64)
        XCTAssertEqual(start.dots.count, max(ring.dots.count, wave.dots.count))
        XCTAssertEqual(positions(start), positions(ring))
        XCTAssertEqual(positions(end), positions(wave))
    }

    func testMidwayDotsHaveLeftTheOldShapeAndAreDrawnFarToNear() {
        let ring = frame(.breathing), bands = frame(.solving)
        let mid = OrbMorph.blend(ring, bands, progress: 0.5, size: 64)
        XCTAssertFalse(positions(mid).isSubset(of: positions(ring)))
        XCTAssertEqual(mid.dots.map(\.z), mid.dots.map(\.z).sorted())
    }

    func testProgressIsClamped() {
        let ring = frame(.breathing), ribbon = frame(.composing)
        XCTAssertEqual(positions(OrbMorph.blend(ring, ribbon, progress: 2, size: 64)), positions(ribbon))
        XCTAssertEqual(positions(OrbMorph.blend(ring, ribbon, progress: -1, size: 64)), positions(ring))
    }
}
