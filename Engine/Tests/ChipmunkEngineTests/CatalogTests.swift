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
        // Level Play packs: 5,000 for 20 boards, scaled by size.
        XCTAssertEqual(catalog.bonus(forPack: "favorites-1"), 5000)
        XCTAssertEqual(catalog.bonus(forPack: "favorites-3"), 2500)
    }

    func testPicturesMatchTheWebGame() {
        // The exported originals (before any redrawn boards from boards.json replace them in play).
        let original = catalog.packs.flatMap(\.levels)
        for i in stride(from: 0, to: catalog.paradiseFrom, by: 7) {
            XCTAssertEqual(original[i].rows, js.decode([String].self, "LEVELS[\(i)].rows"), "board \(i)")
        }
        for r in [0, 7, 19, 20, 33, 59, 140, 259] {
            let (i, base, _) = catalog.paradiseRound(r)
            let expected = js.decode([String].self, "(()=>{const L=LEVELS[\(i)];L.variant=\(r / 20);const rows=L.rows;L.variant=0;return rows})()")
            XCTAssertEqual(base.rows, expected, "Coin Mining round \(r)")
        }
    }

    func testBakedBoardsAreSolvedByTheirPlan() {
        for i in 0..<5 {
            let o = catalog.original(i)
            let summary = try! XCTUnwrap(o.baked, "board \(i) should ship pre-built")
            let lv = assembleLevel(base: o.base, diffKey: o.diffKey, seed: o.seed, summary: summary)
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
        XCTAssertNil(catalog.original(5).baked)
    }

    /// The game has each critter stand a quarter second at its block before heading home. The builder checks boards
    /// without that pause, so make sure the stored plan still clears boards across the whole ramp with it.
    func testPlansStillClearWithThePickupPause() {
        var boards: [(String, Level)] = []
        for i in 0..<5 {
            let b = catalog.original(i)
            boards.append(("baked \(i)", assembleLevel(base: b.base, diffKey: b.diffKey, seed: b.seed, summary: b.baked!)))
        }
        for i in [12, 30, 55, 80, 110, 140, 169] {
            let b = catalog.original(i)
            var o = BuildOptions.game
            o.aim = LevelCatalog.aim(b.diffKey, tailor: 1)
            if let lv = generateLevel(base: b.base, seed: b.seed, diffKey: b.diffKey, options: o) {
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
            // The exported original picture (a redrawn board replaces it in play, but the web game has the original).
            let pic = isPara ? nil : catalog.packs.flatMap(\.levels)[i]
            let base = pic.map { levelBase(name: $0.name, rows: $0.rows, boardNumber: i + 1) }
                ?? catalog.paradiseRound(i - catalog.paradiseFrom).base
            let seed = isPara ? catalog.paradiseRound(i - catalog.paradiseFrom).seed : catalog.original(i).seed
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
