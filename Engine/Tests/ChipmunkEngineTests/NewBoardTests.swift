import XCTest
@testable import ChipmunkEngine

/// The new board maker's boards (Resources/boards.json). Since 2026-11-12 they are all of Level Play: the original 170
/// boards and the clipart packs are retired, but Coin Mining keeps its numbering from 170.
final class NewBoardTests: XCTestCase {
    let catalog = try! LevelCatalog.bundled()

    private struct Raw: Decodable {
        struct Pack: Decodable { let id: String; let levels: [Board] }
        struct Board: Decodable { let id: String; let theme: String; let variant: Int; let source: Source }
        struct Source: Decodable { let license: String?; let foreign_landing_url: String? }
        let packs: [Pack]
    }

    func testOnlyNewBoardsPlay() {
        XCTAssertTrue(catalog.retireOriginals)
        XCTAssertFalse(catalog.newBoards.isEmpty)
        XCTAssertEqual(catalog.paradiseFrom, 170, "Coin Mining keeps its numbering")
        XCTAssertEqual(catalog.levelPlay.map(\.id), (catalog.newBoards + catalog.approvedBoards).map(\.id))
        XCTAssertNil(catalog.baked(forBoard: 0), "the originals' pre-built boards don't apply")
        XCTAssertEqual(Set(catalog.levelPlay.map(\.id)).count, catalog.levelPlay.count, "no board twice")
        XCTAssertEqual(Set(catalog.levelPlay.map(\.name)).count, catalog.levelPlay.count, "no subject twice")
        let mining = Set(catalog.miningBoards.map(\.name))
        XCTAssertEqual(mining.count, catalog.miningBoards.count, "no Coin Mining subject twice")
        XCTAssertTrue(mining.isDisjoint(with: catalog.levelPlay.map(\.name)), "no subject in both modes")
    }

    func testPicturesAreWellFormed() {
        for L in catalog.newBoards + catalog.miningBoards {
            XCTAssertEqual(L.rows.count, 40, L.id)
            XCTAssertTrue(L.rows.allSatisfy { $0.count == 40 }, L.id)
            XCTAssertTrue(L.rows.joined().allSatisfy { PALETTE[$0] != nil }, "\(L.id) uses a color outside the palette")
            XCTAssertLessThanOrEqual(Set(L.rows.joined()).count, 12, "\(L.id) uses more than 12 colors")
        }
    }

    /// Coin Mining plays the new board maker's boards (boards.json "mining"), in the 20 colors, and each one builds
    /// and can be won on its first two laps.
    func testCoinMiningBoards() {
        XCTAssertEqual(catalog.miningBoards.count, 20)
        for r in 0..<(2 * catalog.miningBoards.count) {
            let b = catalog.paradiseRound(r)
            XCTAssertEqual(b.base.rows, catalog.miningBoards[r % 20].rows)
            XCTAssertTrue(b.base.rows.count == 40 && b.base.rows.allSatisfy { $0.count == 40 }, b.base.name)
            XCTAssertTrue(b.base.rows.joined().allSatisfy { PALETTE[$0] != nil }, "\(b.base.name) is off the palette")
            var o = BuildOptions.game
            o.aim = LevelCatalog.aim("paradise", tailor: 1)
            guard let lv = generateLevelRetrying(base: b.base, seed: b.seed, diffKey: "paradise", options: o) else {
                XCTFail("Coin Mining round \(r + 1) (\(b.base.name)) didn't build")
                continue
            }
            var m = Sim(lv)
            m.pickupPause = 25
            XCTAssertNotNil(solve(lv, m, cap: 20000).path, "Coin Mining round \(r + 1) (\(b.base.name)) can't be won")
        }
    }

    /// Boards that still use one of the five retired shades play it as its stand-in color.
    func testRetiredShadesStillPlay() {
        let art = Art(rows: ["QJHEX", "OOCNW"], rocks: nil, lock: false, slots: 5)
        XCTAssertEqual(Set(art.chars), ["O", "C", "N", "W"])
        XCTAssertEqual(art.cells[0], art.cells[5], "deep orange plays as orange")
    }

    /// Past 170 the difficulty keeps climbing steadily (no packs, so no easing every 20 boards).
    func testDifficultyPastTheOriginalRamp() {
        XCTAssertEqual(Difficulty.rampGoal(171), 0.42, accuracy: 0.001)
        for n in 171..<1100 { XCTAssertLessThanOrEqual(Difficulty.rampGoal(n + 1), Difficulty.rampGoal(n), "board \(n + 1)") }
        XCTAssertEqual(Difficulty.rampGoal(1000), 0.16, accuracy: 0.001)
    }

    /// A sample of new boards build (as the game builds them, retrying a few seeds), and each can be won under the
    /// game's timing: its stored plan clears it, or the solver finds a way (the plan is only the solver's first try).
    func testNewBoardsBuildAndClear() {
        for i in stride(from: 0, to: catalog.levelPlay.count, by: 6) {
            let key = catalog.diffKey(forBoard: i)
            var o = BuildOptions.game
            o.aim = LevelCatalog.aim(key, tailor: 1)
            guard let lv = generateLevelRetrying(base: catalog.base(forBoard: i), seed: catalog.seed(forBoard: i),
                                                 diffKey: key, options: o) else {
                XCTFail("board \(i + 1) didn't build")
                continue
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
                XCTAssertNotNil(solve(lv, m0, cap: 20000).path, "board \(i + 1) can't be won")
            }
        }
    }
}
