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
        var b: [Int]
        var left: Int
        var debt: [Int]
    }

    func testSamePocketsAsTheWebGame() {
        loadJS()
        var boards: [(li: Int, board: PickupBoard, id: String)] = []
        for i in [2, 5, 7, 9, 11, 14, 17, 19] { boards.append((i, .warmup(i + 1), catalog.levelPlay[i].id)) }
        for i in [20, 23, 26, 29, 39, 44, 59, 64, 98, 99, 120, 140, 149, 158, 169] {
            boards.append((i, .level(i + 1), catalog.levelPlay[i].id))
        }
        for r in [0, 3, 11, 19] { boards.append((catalog.paradiseFrom + r, .mining, catalog.paradise[r].id)) }
        var total = 0
        for (li, board, id) in boards {
            let seed = (li + 1) * 1000 + 7
            let e = js.decode(Out.self, """
            (()=>{const b=testBase(\(li)),def={...b,...DIFF.normal},a=parseArt(def);lv={...a,slots:5,lanes:[],seed:\(seed)};
              li=\(li);__s=initState(lv);setupPickups();
              return {at:pickups.map(p=>p.i),tools:pickups.map(p=>p.t),keys:pickups.map(p=>p.key),b:Array.from(__s.b),
                left:__s.left,debt:Array.from(__s.debt)}})()
            """)
            let base = js.decode(ParityTests.BaseJSON.self, "testBase(\(li))").base
            let lv = Level(art: Art(base, slots: 5), slots: 5, lanes: [])
            var s = initState(lv)
            let p = placePickups(lv, &s, rows: base.rows, id: id, seed: seed, index: li, board: board, claimed: [])
            let got = Out(at: p.map { $0.at }, tools: p.map { $0.tool }, keys: p.map { $0.key }, b: s.b.map(Int.init), left: s.left,
                          debt: s.debt)
            XCTAssertEqual(got, e, "board \(li)")
            total += p.count
        }
        XCTAssertGreaterThan(total, 20)
    }

    /// The pockets' blocks come off their nests, so the stored plan still clears the board.
    func testBoardsWithBoxesStillClear() {
        for i in [2, 9, 19, 29, 59, 99] {
            let key = catalog.diffKey(forBoard: i)
            let lv: Level
            if let summary = catalog.baked(forBoard: i) {
                lv = assembleLevel(base: catalog.base(forBoard: i), diffKey: key, seed: catalog.seed(forBoard: i),
                                   summary: summary)
            } else {
                var o = BuildOptions.game
                o.aim = LevelCatalog.aim(key, tailor: 1)
                lv = generateLevel(base: catalog.base(forBoard: i), seed: catalog.seed(forBoard: i), diffKey: key, options: o)!
            }
            var m = Sim(lv)
            m.pickupPause = 25
            let p = placePickups(lv, &m.s, rows: catalog.levelPlay[i].rows, id: catalog.levelPlay[i].id,
                                 seed: catalog.seed(forBoard: i), index: i, board: i < 20 ? .warmup(i + 1) : .level(i + 1),
                                 claimed: [])
            XCTAssertFalse(p.isEmpty, "board \(i) should have a box")
            settleTimed(lv, &m)
            for l in lv.plan! {
                if m.s.won { break }
                if !canTap(lv, m.s) { break }
                tap(lv, &m.s, l)
                settleTimed(lv, &m)
            }
            XCTAssertTrue(m.s.won, "board \(i)")
            XCTAssertTrue(p.allSatisfy { $0.reached(m.s) }, "board \(i): every pocket opens by the end")
        }
    }

    func testClaimedBoxesAreNotHandedOutAgain() {
        let i = 29, seed = catalog.seed(forBoard: i)
        let lv = Level(art: Art(catalog.base(forBoard: i), slots: 5), slots: 5, lanes: [])
        var s = initState(lv)
        let first = placePickups(lv, &s, rows: catalog.levelPlay[i].rows, id: catalog.levelPlay[i].id, seed: seed,
                                 index: i, board: .level(i + 1), claimed: [])
        XCTAssertEqual(first.count, 3)
        var s2 = initState(lv)
        let again = placePickups(lv, &s2, rows: catalog.levelPlay[i].rows, id: catalog.levelPlay[i].id, seed: seed,
                                 index: i, board: .level(i + 1), claimed: Set(first.map(\.key)))
        XCTAssertTrue(again.isEmpty)
        XCTAssertEqual(s2.left, initState(lv).left)
    }
}
