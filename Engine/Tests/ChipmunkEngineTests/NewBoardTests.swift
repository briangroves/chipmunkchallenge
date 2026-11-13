import XCTest
@testable import ChipmunkEngine

/// The new board maker's boards (Resources/boards.json), and Level Play's skill-based challenge. Since 2026-11-12 the
/// new boards are all of Level Play: the original 170 boards and the clipart packs are retired, but Coin Mining keeps
/// its numbering from 170.
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
            var count: [Character: Int] = [:]
            for ch in L.rows.joined() where ch != "." { count[ch, default: 0] += 1 }
            XCTAssertGreaterThanOrEqual(count.values.min() ?? 5, MIN_NEST, "\(L.id) has a color under \(MIN_NEST) blocks")
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

    /// The palette is 19 colors; a board still using pale yellow (dropped 2026-11-13) plays it as yellow.
    func testNineteenColors() {
        XCTAssertEqual(PALETTE.count, 19)
        XCTAssertNil(PALETTE["Z"])
        XCTAssertEqual(paletteLetter("Z"), "Y")
    }

    /// The skill rules: warm-ups stay easy, clean wins climb, help holds, five losses ease the next level only, and
    /// the player's pick replaces the automatic change.
    func testSkillRules() {
        var s = Skill()
        XCTAssertEqual(s.goal, 0.97)
        for lv in 1...5 { XCTAssertEqual(s.won(level: lv, boardGoal: s.goal, tries: 1, helped: false), .warmup) }
        XCTAssertEqual(s.goal, 0.97, "the first 5 levels are almost impossible to lose")
        XCTAssertEqual(s.won(level: 6, boardGoal: 0.97, tries: 1, helped: false), .harder)
        XCTAssertEqual(s.goal, 0.95, accuracy: 1e-9)
        XCTAssertEqual(s.won(level: 7, boardGoal: 0.95, tries: 2, helped: false), .harder)
        XCTAssertEqual(s.goal, 0.94, accuracy: 1e-9)
        XCTAssertEqual(s.won(level: 8, boardGoal: 0.94, tries: 1, helped: true), .same, "a tool keeps it the same")
        XCTAssertEqual(s.won(level: 9, boardGoal: 0.94, tries: 3, helped: false), .same, "three tries keeps it the same")
        XCTAssertEqual(s.goal, 0.94, accuracy: 1e-9)
        for _ in 0..<4 { XCTAssertFalse(s.lost()) }
        XCTAssertTrue(s.lost(), "the fifth loss in a row eases the next level")
        XCTAssertEqual(s.goal, 0.98 > Skill.easiest ? Skill.easiest : 0.98, accuracy: 1e-9)
        XCTAssertEqual(Skill.picked(.harder, boardGoal: 0.6, auto: 0.58), 0.55, accuracy: 1e-9)
        XCTAssertEqual(Skill.picked(.same, boardGoal: 0.6, auto: 0.58), 0.6, accuracy: 1e-9)
        XCTAssertEqual(Skill.picked(.easier, boardGoal: 0.6, auto: 0.58), 0.65, accuracy: 1e-9)
        XCTAssertEqual(Skill.picked(.harder, boardGoal: 0.97, auto: 0.97), 0.92, accuracy: 1e-9, "harder works in warm-ups")
        XCTAssertEqual(Skill.picked(.easier, boardGoal: 0.97, auto: 0.97), 0.97, "never easier than the easiest")
        var low = Skill(goal: 0.16)
        _ = low.won(level: 50, boardGoal: 0.16, tries: 1, helped: false)
        XCTAssertEqual(low.goal, Skill.hardest, "never harder than the hardest")
    }

    /// A skill goal plays like the old ramp board that had the same goal, and a lower goal is never easier.
    func testSkillDifficultyFollowsTheRamp() {
        for n in [1, 5, 20, 60, 120, 170] {
            let r = Difficulty.ramp(n), k = Difficulty.skill(Difficulty.rampGoal(n))
            XCTAssertEqual(k.cmin, r.cmin, "board \(n)")
            XCTAssertEqual(k.cmax, r.cmax, "board \(n)")
            XCTAssertEqual(k.pressure, r.pressure, accuracy: 0.011, "board \(n)")
            XCTAssertEqual(k.rtarget, r.rtarget, accuracy: 0.002, "board \(n)")
        }
        var g = Skill.easiest
        while g > Skill.hardest + 0.01 {
            let a = Difficulty.skill(g), b = Difficulty.skill(g - 0.01)
            XCTAssertLessThanOrEqual(b.cgoal!, a.cgoal!)
            XCTAssertLessThanOrEqual(b.cmax, a.cmax)
            XCTAssertGreaterThanOrEqual(b.pressure, a.pressure)
            g -= 0.01
        }
        XCTAssertEqual(Difficulty.named(Difficulty.skillKey(0.6)), Difficulty.skill(0.6))
    }

    /// Boards built the way the game builds them (mystery-box pockets cut, across the skill range) have no nest
    /// smaller than 5.
    func testNoNestsUnderFive() {
        var o = BuildOptions.game
        o.ms = 600
        for (k, g) in [0.97, 0.6, 0.25].enumerated() {
            let key = Difficulty.skillKey(g)
            o.aim = LevelCatalog.baseAim(key)
            for i in stride(from: k, to: catalog.levelPlay.count, by: 4) {
                let cut = pocketBase(catalog.base(forBoard: i), id: catalog.levelPlay[i].id, seed: catalog.seed(forBoard: i),
                                     index: i, board: i < 20 ? .warmup(i + 1) : .level(i + 1), claimed: []).base
                guard let lv = generateLevelRetrying(base: cut, seed: catalog.seed(forBoard: i), diffKey: key, options: o) else {
                    XCTFail("board \(i + 1) didn't build at \(g)")
                    continue
                }
                XCTAssertEqual(lv.small, 0, "board \(i + 1) at \(g): smallest nest \(lv.minNest ?? 0)")
            }
        }
    }

    /// A sample of new boards build (as the game builds them, retrying a few seeds), across the skill range, and each
    /// can be won under the game's timing: its stored plan clears it, or the solver finds a way.
    func testNewBoardsBuildAndClear() {
        let goals = [0.97, 0.8, 0.6, 0.4, 0.25, 0.15]
        for (k, i) in stride(from: 0, to: catalog.levelPlay.count, by: 4).enumerated() {
            let key = Difficulty.skillKey(goals[k % goals.count])
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
