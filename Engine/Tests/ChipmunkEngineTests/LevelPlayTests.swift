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

    /// Levels 1-5 are the same for everyone (they only get easier for a player who keeps losing); from Level 6 the
    /// player's skill factor makes boards harder or easier.
    func testAdaptingStartsAtLevelSix() {
        let k5 = catalog.diffKey(forBoard: 4), k6 = catalog.diffKey(forBoard: 5)
        XCTAssertFalse(LevelCatalog.adapts(k5))
        XCTAssertTrue(LevelCatalog.adapts(k6))
        XCTAssertTrue(LevelCatalog.adapts(catalog.diffKey(forBoard: 30)))
        XCTAssertFalse(LevelCatalog.adapts("daily"))
        XCTAssertEqual(LevelCatalog.aim(k5, tailor: 3), LevelCatalog.baseAim(k5))
        XCTAssertLessThan(LevelCatalog.aim(k5, tailor: 0.6), LevelCatalog.baseAim(k5))
        XCTAssertGreaterThan(LevelCatalog.aim(k6, tailor: 1.5), LevelCatalog.baseAim(k6))
        XCTAssertLessThan(LevelCatalog.aim(k6, tailor: 0.6), LevelCatalog.baseAim(k6))
        XCTAssertEqual(LevelCatalog.aim(k6, tailor: 1), LevelCatalog.baseAim(k6))
    }

    /// Every one of the 50 builds (as the game builds it, retrying a few seeds), can be won under the game's timing
    /// (its stored plan clears it, or the solver finds a way), and comes out close to its place on the ramp: no board
    /// much harder than the ones around it. "Much harder" = the careful player wins over 12 points below the target,
    /// or random taps win under a quarter as often as aimed for.
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
            let d = Difficulty.named(key)
            if lv.botWin! < d.cgoal! - 0.12 || lv.randWin! < d.rtarget * 0.25 {
                lock.lock()
                failed.append(String(format: "board %d (%@) is a spike: careful %.2f vs %.2f, random %.3f vs %.3f", i + 1,
                                     catalog.levelPlay[i].name, lv.botWin!, d.cgoal!, lv.randWin!, d.rtarget))
                lock.unlock()
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
