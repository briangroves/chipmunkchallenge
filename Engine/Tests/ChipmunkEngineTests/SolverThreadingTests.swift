import Foundation
import XCTest
@testable import ChipmunkEngine

/// The Wise Owl solves on a background thread while the game keeps moving critters on the main thread. Routing
/// borrows scratch buffers stored on the Level, so the solver must work on its own copy (sharing one crashed the
/// app on level 56 after a couple of taps).
final class SolverThreadingTests: XCTestCase {
    func testSolverOnACopyWhileTheGamePlaysOn() throws {
        let catalog = try LevelCatalog.bundled()
        let i = 55
        let key = catalog.diffKey(forBoard: i)
        var o = BuildOptions.game
        o.aim = LevelCatalog.aim(key, tailor: 1)
        let lv = try XCTUnwrap(generateLevelRetrying(base: catalog.base(forBoard: i), seed: catalog.seed(forBoard: i),
                                                     diffKey: key, options: o))
        var m = Sim(lv)
        m.pickupPause = 25
        settleTimed(lv, &m)
        tap(lv, &m.s, 0)
        tap(lv, &m.s, 0)
        let start = m
        let copy = lv.copy()
        let done = expectation(description: "solved")
        nonisolated(unsafe) var path: [Int]?
        DispatchQueue.global(qos: .userInitiated).async {
            path = solve(copy, start).path
            done.fulfill()
        }
        // Meanwhile the game keeps simulating on the original level (critters walking, routing every step).
        for _ in 0..<40 {
            if m.s.won || !canTap(lv, m.s) { break }
            settleTimed(lv, &m)
        }
        wait(for: [done], timeout: 120)
        XCTAssertNotNil(path)
        // The copy behaves like the original.
        XCTAssertEqual(solve(lv.copy(), start).path, solve(lv, start).path)
    }
}
