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
        let rows = catalog.levelPlay[0].rows
        XCTAssertNil(levelBase(name: "", rows: rows, boardNumber: LAKE_FROM - 1, terrain: true).water)
        XCTAssertNotNil(levelBase(name: "", rows: rows, boardNumber: LAKE_FROM, terrain: true).water)
        XCTAssertNil(levelBase(name: "", rows: rows, boardNumber: LAKE_FROM, terrain: false).water, "web parity")
        XCTAssertNotNil(catalog.base(forBoard: LAKE_FROM - 1).water, "the first lake board has its lake")
        XCTAssertNotNil(catalog.base(forBoard: BURROW_FROM - 1).burrows, "the first moat board has its burrow")
    }

    /// Every Level Play board from the first boulder board on: the terrain walls nothing in, every colour keeps at
    /// least MIN_NEST blocks, and the board builds and can be won.
    func testTerrainBoardsBuildAndClear() {
        let lp = catalog.levelPlay
        var stats = (lakes: 0, moats: 0, shortcuts: 0, boulders: 0, boards: 0)
        for i in (BOULDERS_FROM - 1)..<min(lp.count, 230) {
            let n = i + 1
            let b = catalog.base(forBoard: i)
            let W = b.rows[0].count, H = b.rows.count
            let solid = Set((b.rocks ?? []) + (b.water ?? []))
            XCTAssertTrue(walledIn(W: W, H: H, solid: solid, burrows: b.burrows ?? []).isEmpty, "board \(n)")
            let art = Art(b, slots: 5)
            XCTAssertGreaterThanOrEqual(art.counts.dropFirst().filter { $0 > 0 }.min() ?? MIN_NEST, MIN_NEST, "board \(n)")
            stats.boards += 1
            if b.water != nil { stats.lakes += 1 }
            if b.water != nil && b.burrows != nil { stats.moats += 1 }
            if b.water == nil && b.burrows != nil { stats.shortcuts += 1 }
            if (b.rocks?.count ?? 0) >= 12 && boulderFor(n) { stats.boulders += 1 }
            if lakeFor(n) || moatFor(n) {
                print("LAKE board \(n): \(moatFor(n) ? "moat" : "pond") -> \(b.water == nil ? "none" : b.burrows == nil ? "pond" : "moat") \(b.water?.count ?? 0)")
            }
            // Building is slow; build every fifth board, plus every board with a burrow.
            guard n % 5 == 0 || b.burrows != nil else { continue }
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
        XCTAssertGreaterThan(stats.lakes, 10)
        XCTAssertGreaterThan(stats.moats, 3)
    }

    /// Debug: print a board's terrain as text. TERRAIN_BOARD=n swift test -c release --filter TerrainTests/testShow
    func testShow() throws {
        guard let v = ProcessInfo.processInfo.environment["TERRAIN_BOARD"], let n = Int(v) else { throw XCTSkip() }
        let b = catalog.base(forBoard: n - 1)
        let water = Set(b.water ?? []), rocks = Set(b.rocks ?? []), bur = Set(b.burrows ?? [])
        let W = b.rows[0].count
        for (r, row) in b.rows.enumerated() {
            print(String(row.enumerated().map { c, ch in
                let i = r * W + c
                return water.contains(i) ? "~" : rocks.contains(i) ? "#" : bur.contains(i) ? "@" : ch == "." ? " " : ch
            }))
        }
    }
}
