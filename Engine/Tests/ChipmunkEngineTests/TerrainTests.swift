import XCTest
@testable import ChipmunkEngine

/// Lakes, boulder fields and burrows (Terrain.swift): the native game's later boards.
final class TerrainTests: XCTestCase {
    let catalog = try! LevelCatalog.bundled()

    /// A 12x12 picture of one colour: the outer ring of blocks, then a water moat, then an island of blocks.
    private func moatBoard(burrow: Bool) -> Level {
        let W = 12, rows = Array(repeating: String(repeating: "R", count: W), count: W)
        var water: [Int] = []
        for r in 2..<10 { for c in 2..<10 where r < 4 || r > 7 || c < 4 || c > 7 { water.append(r * W + c) } }
        // Outer end just outside the moat on the bottom; island end just inside it.
        let bur = burrow ? [10 * W + 5, 7 * W + 5] : nil
        let art = Art(rows: rows, rocks: nil, water: water, burrows: bur, lock: false, slots: 5)
        let lv = Level(art: art, slots: 5, lanes: [[NestSpec(c: 1, n: art.total)]])
        lv.navSetup()
        return lv
    }

    func testWaterIsSolidAndUncounted() {
        let lv = moatBoard(burrow: false)
        XCTAssertEqual(lv.art.cells.filter { $0 == WATER }.count, 48)
        XCTAssertEqual(lv.art.total, 144 - 48)
        let s = initState(lv)
        for i in lv.art.cells.indices where lv.art.cells[i] == WATER {
            XCTAssertEqual(s.o[i], 0)
            XCTAssertEqual(s.ed[i], 0)
        }
    }

    /// Without a burrow the island can't be reached: after eating everything outside, the island's blocks remain.
    /// With one, reaching the outer end opens the island end and the board clears.
    func testBurrowOpensTheIsland() {
        for burrow in [false, true] {
            let lv = moatBoard(burrow: burrow)
            var s = initState(lv)
            while eat(lv, &s, 1) >= 0 {}
            if burrow {
                XCTAssertEqual(s.left, 0, "the island is reached through the burrow")
            } else {
                XCTAssertEqual(s.left, 16, "the island is walled in by water")
            }
        }
    }

    /// A critter fetching an island block walks out, down the burrow (out of sight for a moment) and up on the island.
    func testCrittersWalkThroughBurrows() {
        let lv = moatBoard(burrow: true)
        var m = Sim(lv)
        tap(lv, &m.s, 0)
        var sawTunnel = false
        var underground = false
        while !m.s.won {
            let e = nextEvent(lv, &m)
            if e == .infinity { break }
            processTick(lv, &m, e, SimObserver(spawn: { a in
                for k in 0..<(a.p1.count - 1) where tunnelStep(lv, a.p1, k) { sawTunnel = true }
                // Every step is to a neighbour, a wait at a burrow's end, or a jump to its other end.
                for k in 0..<(a.p1.count - 1) {
                    let x = a.p1[k], y = a.p1[k + 1]
                    let near = abs(x % lv.NW - y % lv.NW) + abs(x / lv.NW - y / lv.NW) == 1
                    XCTAssertTrue(near || tunnelStep(lv, a.p1, k))
                }
            }))
            for a in m.ants where antUnderground(lv, a, at: m.tick + 1) { underground = true }
        }
        settleTimed(lv, &m)
        XCTAssertTrue(m.s.won)
        XCTAssertTrue(sawTunnel)
        XCTAssertTrue(underground)
    }

    func testFirstBoardsOfEachFeature() {
        // Water only from LAKE_FROM, only on pictures known to draw it, and never in the web game's boards.
        let i = (LAKE_FROM - 1..<catalog.levelPlay.count).first { catalog.drawsWater($0) }!
        let rows = catalog.levelPlay[i].rows
        XCTAssertNil(levelBase(name: "", rows: rows, boardNumber: LAKE_FROM - 1, terrain: true, drawsWater: true).water)
        XCTAssertNotNil(levelBase(name: "", rows: rows, boardNumber: LAKE_FROM, terrain: true, drawsWater: true).water)
        XCTAssertNil(levelBase(name: "", rows: rows, boardNumber: LAKE_FROM, terrain: true, drawsWater: false).water,
                     "blue alone never makes a lake")
        XCTAssertNil(levelBase(name: "", rows: rows, boardNumber: LAKE_FROM, terrain: false, drawsWater: true).water,
                     "web parity")
        XCTAssertNotNil(catalog.base(forBoard: i).water)
        XCTAssertNotNil(catalog.base(forBoard: BURROW_FROM - 1).burrows, "the first burrow board has its burrow")
    }

    /// Night sky, sky between the subject's parts, snow shading and fences are blue but not water.
    func testSkyIsNeverWater() {
        for name in ["Bush Baby", "Indigo Bunting", "Barn Owlet", "Sugar Glider", "Little Gargoyle", "Reindeer Calf",
                     "Tiny Sphinx", "Barn Kitten", "Gray Fox Kit"] {
            guard let i = catalog.levelPlay.firstIndex(where: { $0.name == name }) else { continue }
            XCTAssertFalse(catalog.drawsWater(i), name)
            XCTAssertNil(catalog.base(forBoard: i).water, name)
        }
        // Every listed picture is still in the game and its water is found.
        let ids = Set(catalog.levelPlay.map(\.id))
        XCTAssertTrue(catalog.waterBoards.isSubset(of: ids))
        for (i, p) in catalog.levelPlay.enumerated() where catalog.drawsWater(i) {
            XCTAssertFalse(drawnWater(p.rows).isEmpty, "\(p.name): listed as drawing water, but none found")
        }
    }

    /// Which pictures draw water, over every Level Play board (run it to see; the lake boards are checked by eye
    /// with testShow).
    func testDrawnWaterSurvey() {
        var found = 0
        for (i, p) in catalog.levelPlay.enumerated() {
            let w = drawnWater(p.rows)
            if w.isEmpty { continue }
            found += 1
            let W = p.rows[0].count
            let top = w.map { $0 / W }.min()!, bottom = w.map { $0 / W }.max()!
            print("WATER board \(i + 1) \(p.name): \(w.count) cells, rows \(top)-\(bottom)")
        }
        print("WATER found on \(found) of \(catalog.levelPlay.count) pictures")
    }

    /// Every Level Play board from the first boulder board on: the terrain walls nothing in, every colour keeps at
    /// least MIN_NEST blocks, and the board builds and can be won.
    func testTerrainBoardsBuildAndClear() {
        let lp = catalog.levelPlay
        var stats = (lakes: 0, islands: 0, burrowBoards: 0, twoBurrows: 0, boulders: 0, boards: 0)
        for i in (BOULDERS_FROM - 1)..<lp.count {
            let n = i + 1
            let b = catalog.base(forBoard: i)
            let W = b.rows[0].count, H = b.rows.count
            let solid = Set((b.rocks ?? []) + (b.water ?? []))
            let shut = walledIn(W: W, H: H, solid: solid, burrows: b.burrows ?? [])
            XCTAssertTrue(shut.allSatisfy { b.rows[$0 / W][b.rows[$0 / W].index(b.rows[$0 / W].startIndex, offsetBy: $0 % W)] == "." },
                          "board \(n) walls blocks in")
            let art = Art(b, slots: 5)
            XCTAssertGreaterThanOrEqual(art.counts.dropFirst().filter { $0 > 0 }.min() ?? MIN_NEST, MIN_NEST, "board \(n)")
            if let w = b.water {
                XCTAssertEqual(Set(w), drawnWater(lp[i].rows), "board \(n): water is only what the picture draws")
            }
            stats.boards += 1
            let water = Set(b.water ?? [])
            let pairs = (b.burrows ?? []).count / 2
            let byWater = stride(from: 0, to: (b.burrows ?? []).count, by: 2).filter { k in
                [b.burrows![k], b.burrows![k + 1]].contains { i in neighbors(i, W: W, H: H).contains { water.contains($0) } }
            }.count
            if !water.isEmpty { stats.lakes += 1 }
            if byWater > 0 { stats.islands += 1 }
            if pairs - byWater > 0 { stats.burrowBoards += 1 }
            if pairs - byWater > 1 { stats.twoBurrows += 1 }
            if (b.rocks?.count ?? 0) >= 12 && boulderFor(n) { stats.boulders += 1 }
            // Building is slow; build every fifth board, plus every board with water or a burrow.
            guard n % 5 == 0 || b.burrows != nil || b.water != nil else { continue }
            let key = catalog.diffKey(forBoard: i)
            var o = BuildOptions.game
            o.aim = LevelCatalog.baseAim(key)
            guard let lv = generateLevelRetrying(base: b, seed: catalog.seed(forBoard: i), diffKey: key, options: o) else {
                XCTFail("board \(n) didn't build")
                continue
            }
            var m = Sim(lv)
            m.pickupPause = 25
            XCTAssertNotNil(solve(lv, m, cap: 20000).path, "board \(n) can't be won")
        }
        print("TERRAIN", stats)
        XCTAssertGreaterThan(stats.burrowBoards, (lp.count - BURROW_FROM) / 4, "burrows on a fair share of boards")
    }

    /// Debug: print a board's picture and its terrain side by side.
    /// TERRAIN_BOARD=n swift test -c release --filter TerrainTests/testShow
    func testShow() throws {
        guard let v = ProcessInfo.processInfo.environment["TERRAIN_BOARD"], let n = Int(v) else { throw XCTSkip() }
        let b = catalog.base(forBoard: n - 1), pic = catalog.levelPlay[n - 1]
        let water = Set(b.water ?? []), rocks = Set(b.rocks ?? []), bur = Set(b.burrows ?? [])
        let W = b.rows[0].count
        print("SHOW \(n) \(pic.name)")
        for (r, row) in b.rows.enumerated() {
            let t = String(row.enumerated().map { c, ch in
                let i = r * W + c
                return water.contains(i) ? "~" : rocks.contains(i) ? "#" : bur.contains(i) ? "@" : ch == "." ? " " : ch
            })
            print("SHOW " + pic.rows[r] + "  " + t)
        }
    }
}
