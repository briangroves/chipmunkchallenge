import CryptoKit
import XCTest
@testable import ChipmunkEngine

/// Checks the exported level catalog against the web game it came from.
final class CatalogTests: XCTestCase {
    let js = JSReference.shared
    let catalog = try! LevelCatalog.bundled()

    func testExportIsUpToDate() throws {
        let html = try Data(contentsOf: JSReference.repoRoot.appendingPathComponent("web/chipmunk-challenge.html"))
        let sha = SHA256.hash(data: html).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(catalog.source, sha, "web/chipmunk-challenge.html changed: run tools/export_levels.sh")
    }

    func testShape() {
        let original = catalog.packs.flatMap(\.levels)
        XCTAssertEqual(original.count, js.decode(Int.self, "RAMP_N"))
        XCTAssertEqual(catalog.paradiseFrom, js.decode(Int.self, "PARADISE_FROM"))
        XCTAssertEqual(catalog.paradise.count, js.decode(Int.self, "LEVELS.filter(L=>L.pack==='paradise').length"))
        XCTAssertEqual(catalog.packs.map(\.id), js.decode([String].self, "PACKS.map(p=>p.id)"))
        XCTAssertEqual(catalog.packs.map(\.name), js.decode([String].self, "PACKS.map(p=>p.name)"))
        XCTAssertEqual(original.map(\.name), js.decode([String].self, "LEVELS.slice(0,RAMP_N).map(L=>L.name)"))
        XCTAssertEqual(catalog.bonus(forPack: "storybook"), 2500)
        XCTAssertEqual(catalog.bonus(forPack: "food"), 5000)
    }

    func testPicturesMatchTheWebGame() {
        for i in stride(from: 0, to: catalog.paradiseFrom, by: 7) {
            XCTAssertEqual(catalog.levelPlay[i].rows, js.decode([String].self, "LEVELS[\(i)].rows"), "board \(i)")
        }
        for r in [0, 7, 19, 20, 33, 59, 140, 259] {
            let (i, base, _) = catalog.paradiseRound(r)
            let expected = js.decode([String].self, "(()=>{const L=LEVELS[\(i)];L.variant=\(r / 20);const rows=L.rows;L.variant=0;return rows})()")
            XCTAssertEqual(base.rows, expected, "Coin Mining round \(r)")
        }
    }

    func testBakedBoardsAreSolvedByTheirPlan() {
        for i in 0..<5 {
            let summary = try! XCTUnwrap(catalog.baked(forBoard: i), "board \(i) should ship pre-built")
            let lv = assembleLevel(base: catalog.base(forBoard: i), diffKey: catalog.diffKey(forBoard: i),
                                   seed: catalog.seed(forBoard: i), summary: summary)
            XCTAssertEqual(lv.seed, summary.seed)
            var m = Sim(lv)
            settleTimed(lv, &m)
            for l in lv.plan! {
                if m.s.won { break }
                XCTAssertTrue(canTap(lv, m.s))
                tap(lv, &m.s, l)
                settleTimed(lv, &m)
            }
            XCTAssertTrue(m.s.won, "board \(i)")
        }
        XCTAssertNil(catalog.baked(forBoard: 5))
    }

    /// The game has each critter stand a quarter second at its block before heading home. The builder checks boards
    /// without that pause, so make sure the stored plan still clears boards across the whole ramp with it.
    func testPlansStillClearWithThePickupPause() {
        var boards: [(String, Level)] = []
        for i in 0..<5 {
            let summary = catalog.baked(forBoard: i)!
            boards.append(("baked \(i)", assembleLevel(base: catalog.base(forBoard: i), diffKey: catalog.diffKey(forBoard: i),
                                                       seed: catalog.seed(forBoard: i), summary: summary)))
        }
        for i in [12, 30, 55, 80, 110, 140, 169] {
            let key = catalog.diffKey(forBoard: i)
            var o = BuildOptions.game
            o.aim = LevelCatalog.aim(key, tailor: 1)
            if let lv = generateLevel(base: catalog.base(forBoard: i), seed: catalog.seed(forBoard: i), diffKey: key, options: o) {
                boards.append(("board \(i)", lv))
            }
        }
        for r in [0, 5, 23] {
            let b = catalog.paradiseRound(r)
            var o = BuildOptions.game
            o.aim = LevelCatalog.baseAim("paradise")
            if let lv = generateLevel(base: b.base, seed: b.seed, diffKey: "paradise", options: o) {
                boards.append(("mining \(r)", lv))
            }
        }
        XCTAssertGreaterThan(boards.count, 10)
        for (name, lv) in boards {
            var m = Sim(lv)
            m.pickupPause = 25
            settleTimed(lv, &m)
            for l in lv.plan! {
                if m.s.won { break }
                XCTAssertTrue(canTap(lv, m.s), name)
                if !canTap(lv, m.s) { break }
                tap(lv, &m.s, l)
                settleTimed(lv, &m)
            }
            XCTAssertTrue(m.s.won, name)
        }
    }

    func testAim() {
        for key in ["warm3", "lv40", "lv170", "paradise", "normal"] {
            XCTAssertEqual(LevelCatalog.baseAim(key), js.decode(Double.self, "Math.round(10/DIFF['\(key)'].rtarget)/10"), key)
        }
        XCTAssertEqual(LevelCatalog.aim("warm3", tailor: 3), LevelCatalog.baseAim("warm3"))
        XCTAssertEqual(LevelCatalog.aim("lv40", tailor: 1),
                       js.decode(Double.self, "Math.min(300,Math.max(1.1,Math.round(10*1/DIFF.lv40.rtarget)/10))"))
    }

    /// A board built from the catalog is the same board the web game builds.
    func testCatalogBuildsTheSameBoard() {
        for i in [29, 64, 171 - 1] {
            let isPara = i >= catalog.paradiseFrom
            let key = isPara ? "paradise" : catalog.diffKey(forBoard: i)
            let base = isPara ? catalog.paradiseRound(i - catalog.paradiseFrom).base : catalog.base(forBoard: i)
            let seed = isPara ? catalog.paradiseRound(i - catalog.paradiseFrom).seed : catalog.seed(forBoard: i)
            let aim = LevelCatalog.aim(key, tailor: 1)
            var o = ParityTests.quick
            o.aim = aim
            let expected = js.decode(LevelSummary?.self, """
            (()=>{const lv=generateLevel(testBase(\(i)),\(seed),'\(key)',{...\(ParityTests.quickJS),aim:\(aim)});return lv&&levelSummary(lv)})()
            """)
            XCTAssertNotNil(expected)
            XCTAssertEqual(generateLevel(base: base, seed: seed, diffKey: key, options: o)?.summary, expected, "board \(i)")
        }
    }
}
