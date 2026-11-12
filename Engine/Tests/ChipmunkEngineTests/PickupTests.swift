import XCTest
@testable import ChipmunkEngine

/// Mystery boxes: the Swift port cuts the same pockets as the web game, and boards stay solvable with them.
final class PickupTests: XCTestCase {
    let js = JSReference.shared
    let catalog = try! LevelCatalog.bundled()

    /// Loads the web game's box code (PICK_SCHED through setupPickups) with stand-ins for the page around it.
    private func loadJS() {
        let html = try! String(contentsOf: JSReference.repoRoot.appendingPathComponent("web/chipmunk-challenge.html"),
                               encoding: .utf8)
        let from = html.range(of: "const PICK_SCHED=")!
        let to = html.range(of: "function checkPickups(", range: from.upperBound..<html.endIndex)!
        js.run("""
        var lv=null,li=0,deadTok=0,lockWas=false,__s=null;function setDead(){}function $(){return null}
        function st(){return __s}const isPara=L=>!!L&&L.pack==='paradise';const store={get:(k,d)=>d,set(){}};
        """)
        js.run(String(html[from.lowerBound..<to.lowerBound]))
    }

    private struct Out: Decodable, Equatable {
        var at: [Int]
        var tools: [String]
        var keys: [String]
    }

    func testSameBoxesAsTheWebGame() {
        loadJS()
        var boards: [(li: Int, board: PickupBoard, id: String)] = []
        // The exported originals: the web game has these pictures even where boards.json redraws one.
        let original = catalog.packs.flatMap(\.levels)
        for i in [2, 5, 7, 9, 11, 14, 17, 19] { boards.append((i, .warmup(i + 1), original[i].id)) }
        for i in [20, 23, 26, 29, 39, 44, 59, 64, 98, 99, 120, 140, 149, 158, 169] {
            boards.append((i, .level(i + 1), original[i].id))
        }
        for r in [0, 3, 11, 19] { boards.append((catalog.paradiseFrom + r, .mining, catalog.paradise[r].id)) }
        var total = 0
        for (li, board, id) in boards {
            let seed = (li + 1) * 1000 + 7
            let e = js.decode(Out.self, """
            (()=>{const b=testBase(\(li)),def={...b,...DIFF.normal},a=parseArt(def);lv={...a,slots:5,lanes:[],seed:\(seed)};
              li=\(li);__s=initState(lv);setupPickups();
              return {at:pickups.map(p=>p.i),tools:pickups.map(p=>p.t),keys:pickups.map(p=>p.key)}})()
            """)
            let base = js.decode(ParityTests.BaseJSON.self, "testBase(\(li))").base
            let lv = Level(art: Art(base, slots: 5), slots: 5, lanes: [])
            let s = initState(lv)
            let p = placePickups(lv, s, rows: base.rows, id: id, seed: seed, index: li, board: board, claimed: [])
            XCTAssertEqual(Out(at: p.map { $0.at }, tools: p.map { $0.tool }, keys: p.map { $0.key }), e, "board \(li)")
            XCTAssertTrue(p.allSatisfy { $0.cells.allSatisfy { s.b[$0] != 0 && s.b[$0] != ROCK } }, "board \(li)")
            total += p.count
        }
        XCTAssertGreaterThan(total, 20)
    }

    /// Boards built from a picture with its pockets cut out: the stored solution clears each one (with the pickup
    /// pause), and the open area reaches every pocket on the way. These daily boards' solutions failed when the web
    /// game's way (cutting the pocket out of a finished board) was used.
    func testBoardsWithPocketsClear() {
        var boards: [(name: String, base: LevelBase, key: String, seed: Int, id: String, index: Int, board: PickupBoard)] = []
        let daily = catalog.paradiseFrom + catalog.paradise.count
        for day in [20764, 20765, 20766] {
            let r = RNG(seed: day &* 2_654_435 &+ 11)
            let pool = catalog.dailyPool
            let pic = pool[r.int(pool.count)]
            let rampN = 50 + r.int(61)
            var diff = Difficulty.ramp(rampN)
            diff.label = "Daily"
            Difficulty.custom["daily"] = diff
            let p = catalog.levelPlay[pic]
            boards.append(("day \(day)", levelBase(name: p.name, rows: p.rows, boardNumber: rampN), "daily", day * 7 + 1,
                           "daily", daily, .daily))
        }
        for i in [2, 29, 44] {
            boards.append(("board \(i)", catalog.base(forBoard: i), catalog.diffKey(forBoard: i),
                           (i + 1) * 1000 + 7, catalog.levelPlay[i].id, i, i < 20 ? .warmup(i + 1) : .level(i + 1)))
        }
        for b in boards {
            let (base, pockets) = pocketBase(b.base, id: b.id, seed: b.seed, index: b.index, board: b.board, claimed: [])
            XCTAssertFalse(pockets.isEmpty, b.name)
            var o = BuildOptions.game
            o.aim = LevelCatalog.aim(b.key, tailor: 1)
            let lv = generateLevel(base: base, seed: b.seed, diffKey: b.key, options: o)!
            var m = Sim(lv)
            m.pickupPause = 25
            // The pockets are empty and sealed until the open area reaches them.
            XCTAssertTrue(pockets.allSatisfy { p in p.cells.allSatisfy { m.s.b[$0] == 0 && m.s.o[$0] == 0 } }, b.name)
            var got = Set<Int>()
            settleTimed(lv, &m)
            for l in lv.plan! {
                if m.s.won || !canTap(lv, m.s) { break }
                tap(lv, &m.s, l)
                settleTimed(lv, &m)
                for (k, p) in pockets.enumerated() where p.reached(m.s) { got.insert(k) }
            }
            XCTAssertTrue(m.s.won, b.name)
            XCTAssertEqual(got.count, pockets.count, b.name)
        }
    }

    func testClaimedBoxesAreNotHandedOutAgain() {
        let i = 29, seed = catalog.seed(forBoard: i)
        let lv = Level(art: Art(catalog.base(forBoard: i), slots: 5), slots: 5, lanes: [])
        let s = initState(lv)
        let first = placePickups(lv, s, rows: catalog.levelPlay[i].rows, id: catalog.levelPlay[i].id, seed: seed,
                                 index: i, board: .level(i + 1), claimed: [])
        XCTAssertEqual(first.count, 3)
        let again = placePickups(lv, s, rows: catalog.levelPlay[i].rows, id: catalog.levelPlay[i].id, seed: seed,
                                 index: i, board: .level(i + 1), claimed: Set(first.map(\.key)))
        XCTAssertTrue(again.isEmpty)
    }
}
