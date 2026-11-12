import XCTest
@testable import ChipmunkEngine

/// The 50 boards Level Play starts with (Resources/levelplay.json); later boards are downloaded (BoardPackTests).
final class LevelPlayTests: XCTestCase {
    let catalog = try! LevelCatalog.bundled()

    func testFiftyBoardsInPacks() {
        XCTAssertEqual(catalog.starterCount, 50)
        XCTAssertEqual(catalog.levelPlay.count, 50)
        XCTAssertEqual(catalog.starterPacks.map(\.levels.count), [20, 20, 10])
        XCTAssertEqual(catalog.paradiseFrom, 170, "Coin Mining keeps its numbering")
        XCTAssertEqual(catalog.dailyPool, Array(5..<50))
        XCTAssertEqual(Set(catalog.levelPlay.map(\.id)).count, 50, "board ids are unique")
        XCTAssertEqual(Set(catalog.levelPlay.map { $0.name.lowercased() }).count, 50, "no subject twice")
    }

    func testPicturesAreWellFormed() {
        for p in catalog.levelPlay {
            XCTAssertTrue(BoardPacks.wellFormed(p), p.id)
        }
    }

    /// The difficulty past 170 eases in at the start of each pack and climbs within it.
    func testDifficultyPastTheOriginalRamp() {
        XCTAssertEqual(Difficulty.rampGoal(171), 0.42, accuracy: 0.001)
        XCTAssertLessThan(Difficulty.rampGoal(190), Difficulty.rampGoal(171))
        XCTAssertGreaterThan(Difficulty.rampGoal(191), Difficulty.rampGoal(190), "a new pack starts gentler")
        XCTAssertLessThan(Difficulty.rampGoal(1000), Difficulty.rampGoal(190))
        XCTAssertGreaterThan(Difficulty.rampGoal(1000), 0.1)
    }

    /// Every one of the 50 builds (as the game builds it, retrying a few seeds) and can be won under the game's
    /// timing: its stored plan clears it, or the solver finds a way (the plan is only the solver's first try).
    func testEveryBoardBuildsAndClears() {
        let lock = NSLock()
        var failed: [String] = []
        DispatchQueue.concurrentPerform(iterations: catalog.levelPlay.count) { i in
            let key = catalog.diffKey(forBoard: i)
            var o = BuildOptions.game
            o.aim = LevelCatalog.aim(key, tailor: 1)
            guard let lv = generateLevelRetrying(base: catalog.base(forBoard: i), seed: catalog.seed(forBoard: i),
                                                 diffKey: key, options: o) else {
                lock.lock(); failed.append("board \(i + 1) didn't build"); lock.unlock()
                return
            }
            var m = Sim(lv)
            m.pickupPause = 25
            settleTimed(lv, &m)
            for l in lv.plan! {
                if m.s.won || !canTap(lv, m.s) { break }
                tap(lv, &m.s, l)
                settleTimed(lv, &m)
            }
            if !m.s.won {
                var m0 = Sim(lv)
                m0.pickupPause = 25
                if solve(lv, m0, cap: 20000).path == nil {
                    lock.lock(); failed.append("board \(i + 1) can't be won"); lock.unlock()
                }
            }
        }
        XCTAssertEqual(failed.sorted(), [])
    }
}
