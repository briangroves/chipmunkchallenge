import XCTest
@testable import ChipmunkEngine

/// Checks the Swift engine against the original JavaScript, step by step. Level building draws thousands of random
/// numbers and breaks many ties; any drift shows up here as a different board.
final class ParityTests: XCTestCase {
    let js = JSReference.shared

    /// JSON-friendly form of a board base.
    struct BaseJSON: Decodable {
        var name: String
        var rows: [String]
        var rocks: [Int]?
        var lock: Bool?
        var lockOK: Bool?

        var base: LevelBase {
            LevelBase(name: name, rows: rows, rocks: rocks, lock: lock ?? false, lockOK: lockOK ?? false)
        }
    }

    func jsBase(_ i: Int) -> LevelBase {
        js.decode(BaseJSON.self, "testBase(\(i))").base
    }

    // MARK: - Building blocks

    func testRandomNumbers() {
        for seed in [0, 1, 7, 12345, 4_294_967_295, 99_999_999_999, -5] {
            let expected = js.decode([Double].self, "(()=>{const r=rngFrom(\(seed));return Array.from({length:50},()=>r())})()")
            let r = RNG(seed: seed)
            XCTAssertEqual((0..<50).map { _ in r.next() }, expected, "seed \(seed)")
        }
    }

    func testDifficultyTable() {
        struct D: Decodable {
            var label: String, slots: Int, lanes: Int, cmin: Int, cmax: Int, target: Double, rtarget: Double
            var ctarget: Double?, cgoal: Double?, pressure: Double
        }
        var keys = ["easy", "normal", "paradise", "hard"]
        keys += (1...Difficulty.rampN).map(Difficulty.rampKey)
        for key in keys {
            let e = js.decode(D.self, "DIFF['\(key)']")
            let d = Difficulty.named(key)
            XCTAssertEqual(d.label, e.label, key)
            XCTAssertEqual([d.slots, d.lanes, d.cmin, d.cmax], [e.slots, e.lanes, e.cmin, e.cmax], key)
            XCTAssertEqual(d.target, e.target, key)
            XCTAssertEqual(d.rtarget, e.rtarget, key)
            XCTAssertEqual(d.ctarget, e.ctarget, key)
            XCTAssertEqual(d.cgoal, e.cgoal, key)
            XCTAssertEqual(d.pressure, e.pressure, key)
        }
    }

    func testRocksAndLocks() {
        let n = js.decode(Int.self, "RAMP_N")
        for i in 0..<n {
            let jsB = jsBase(i)
            let b = levelBase(name: jsB.name, rows: jsB.rows, boardNumber: i + 1)
            XCTAssertEqual(b, jsB, "board \(i + 1)")
        }
    }

    func testPictureAndOpening() {
        for i in [0, 24, 33, 70, 120, 169, 175] {
            let b = jsBase(i)
            struct E: Decodable {
                var W: Int, H: Int, cells: [Int], chars: [String], counts: [Int], total: Int, key: [Int]
                var heaps: [[Int]], o: [Int], ed: [Int], left: Int
            }
            let e = js.decode(E.self, """
            (()=>{const b=testBase(\(i)),def={...b,...DIFF.normal},a=parseArt(def),lv={...a,slots:5,lanes:[]};const s=initState(lv);
              return {W:a.W,H:a.H,cells:Array.from(a.cells),chars:a.chars,counts:a.counts,total:a.total,key:Array.from(a.key),
                heaps:s.hp.map(h=>h.slice().sort((x,y)=>x-y)),o:Array.from(s.o),ed:Array.from(s.ed),left:s.left}})()
            """)
            let art = Art(b, slots: 5)
            XCTAssertEqual(art.W, e.W)
            XCTAssertEqual(art.H, e.H)
            XCTAssertEqual(art.cells.map(Int.init), e.cells, "board \(i)")
            XCTAssertEqual(art.chars.map(String.init), e.chars)
            XCTAssertEqual(art.counts, e.counts)
            XCTAssertEqual(art.total, e.total)
            XCTAssertEqual(art.key, e.key)
            let s = initState(Level(art: art, slots: 5, lanes: []))
            XCTAssertEqual(s.hp.map { $0.sorted() }, e.heaps, "board \(i)")
            XCTAssertEqual(s.o.map(Int.init), e.o)
            XCTAssertEqual(s.ed.map(Int.init), e.ed)
            XCTAssertEqual(s.left, e.left)
        }
    }

    // MARK: - Builder

    func testBuildSequence() {
        for (i, key, seed) in [(0, "warm1", 11), (40, "lv41", 3), (60, "lv61", 8), (100, "normal", 21), (175, "paradise", 5)] {
            let b = jsBase(i)
            for relax in [false, true] {
                for pressure in [0.0, 0.7] {
                    let e = js.json("""
                    (()=>{const b=testBase(\(i)),def={...b,...DIFF['\(key)']};return buildSequence(parseArt(def),def,rngFrom(\(seed)),\(relax),\(pressure))})()
                    """)
                    var def = Difficulty.named(key)
                    def.lock = b.lock
                    let seq = buildSequence(Art(b, slots: def.slots), def, RNG(seed: seed), relax, pressure)
                    let expected = try! JSONDecoder().decode([NestSpec]?.self, from: Data(e.utf8))
                    XCTAssertEqual(seq, expected, "board \(i) \(key) relax \(relax) pressure \(pressure)")
                }
            }
        }
    }

    /// Small, time-unlimited builds so both engines do exactly the same work.
    static var quick: BuildOptions {
        var o = BuildOptions()
        o.seqs = 2
        o.iters = 10
        o.K = 12
        o.V = 24
        o.RV = 24
        o.CV = 24
        o.ms = 1e12
        return o
    }

    static let quickJS = "{seqs:2,iters:10,K:12,V:24,RV:24,CV:24,ms:1e12}"

    static let boards: [(i: Int, key: String, seed: Int)] = [
        (0, "warm1", 1007), (29, "lv30", 30007), (49, "lv50", 50007), (89, "lv90", 90008), (140, "lv141", 4),
        (170, "paradise", 171_007), (110, "normal", 9), (12, "easy", 2), (60, "hard", 61),
    ]

    func testGenerateLevel() {
        for (i, key, seed) in Self.boards {
            let b = jsBase(i)
            let expected = js.decode(LevelSummary?.self,
                                     "(()=>{const lv=generateLevel(testBase(\(i)),\(seed),'\(key)',\(Self.quickJS));return lv&&levelSummary(lv)})()")
            let lv = generateLevel(base: b, seed: seed, diffKey: key, options: Self.quick)
            XCTAssertNotNil(expected, "JS built no board \(i)")
            XCTAssertGreaterThan(expected?.nests ?? 0, 5)
            XCTAssertEqual(lv?.summary, expected, "board \(i) \(key)")
        }
    }

    func testGenerateLevelWithAim() {
        let b = jsBase(70)
        var o = Self.quick
        o.aim = 2.5
        let expected = js.decode(LevelSummary?.self,
                                 "(()=>{const lv=generateLevel(testBase(70),77,'lv71',{...\(Self.quickJS),aim:2.5});return lv&&levelSummary(lv)})()")
        XCTAssertEqual(generateLevel(base: b, seed: 77, diffKey: "lv71", options: o)?.summary, expected)
    }

    // MARK: - Timed simulation and solver

    /// The same board in both engines, from a JS-built summary.
    func sharedBoard(_ i: Int, _ key: String, _ seed: Int) -> Level {
        let text = js.json("levelSummary(generateLevel(testBase(\(i)),\(seed),'\(key)',\(Self.quickJS)))")
        let summary = try! JSONDecoder().decode(LevelSummary.self, from: Data(text.utf8))
        js.run("var SB=assembleLevel(testBase(\(i)),'\(key)',\(seed),\(text));")
        return assembleLevel(base: jsBase(i), diffKey: key, seed: seed, summary: summary)
    }

    struct Event: Decodable, Equatable {
        var e: String
        var t: Double
        var i: Int
        var id: Int
        var p: Int
    }

    func trace(_ lv: Level, _ order: [Int]) -> (events: [Event], left: Int) {
        var events: [Event] = []
        let cb = SimObserver(
            spawn: { events.append(Event(e: "s", t: $0.ta, i: $0.i, id: $0.id, p: $0.p1.count)) },
            arrive: { events.append(Event(e: "a", t: $0.th, i: $0.i, id: $0.id, p: $0.p2?.count ?? 0)) },
            home: { events.append(Event(e: "h", t: $0.th, i: $0.i, id: $0.id, p: 0)) })
        var m = Sim(lv)
        settleTimed(lv, &m, cb)
        for l in order {
            if m.s.left == 0 || !canTap(lv, m.s) || m.s.lp[l] >= lv.lanes[l].count { break }
            tap(lv, &m.s, l)
            settleTimed(lv, &m, cb)
        }
        return (events, m.s.left)
    }

    func jsTrace(_ order: [Int]) -> (events: [Event], left: Int) {
        struct T: Decodable { var events: [Event]; var left: Int }
        let t = js.decode(T.self, """
        (()=>{const lv=SB,ev=[];const cb={spawn:a=>ev.push({e:'s',t:a.ta,i:a.i,id:a.id,p:a.p1.length}),
          arrive:a=>ev.push({e:'a',t:a.th,i:a.i,id:a.id,p:a.p2?a.p2.length:0}),home:a=>ev.push({e:'h',t:a.th,i:a.i,id:a.id,p:0})};
          const m=newSim(lv);settleTimed(lv,m,cb);
          for(const l of \(order)){if(m.s.left===0||!canTap(lv,m.s)||m.s.lp[l]>=lv.lanes[l].length)break;tap(lv,m.s,l);settleTimed(lv,m,cb)}
          return {events:ev,left:m.s.left}})()
        """)
        return (t.events, t.left)
    }

    func testTimedSimulationFollowsThePlan() {
        for (i, key, seed) in [(0, "warm1", 1007), (49, "lv50", 50007), (170, "paradise", 171_007)] {
            let lv = sharedBoard(i, key, seed)
            let plan = lv.plan!
            let (ev, left) = trace(lv, plan)
            let (jev, jleft) = jsTrace(plan)
            XCTAssertEqual(left, 0, "plan should clear board \(i)")
            XCTAssertEqual(left, jleft)
            XCTAssertGreaterThan(ev.count, 300, "board \(i)")
            XCTAssertEqual(ev.count, jev.count, "board \(i)")
            XCTAssertEqual(ev, jev, "board \(i)")
        }
    }

    func testTimedSimulationOffPlan() {
        let lv = sharedBoard(89, "lv90", 90008)
        let order = [0, 1, 2, 3, 3, 2, 1, 0, 0, 0, 1, 1, 2, 2, 3, 3]
        let (ev, left) = trace(lv, order)
        let (jev, jleft) = jsTrace(order)
        XCTAssertEqual(left, jleft)
        XCTAssertEqual(ev, jev)
    }

    func testSolver() {
        struct S: Decodable { var path: [Int]?; var nodes: Int; var aborted: Bool; var via: String }
        for (i, key, seed) in [(0, "warm1", 1007), (49, "lv50", 50007), (89, "lv90", 90008)] {
            let lv = sharedBoard(i, key, seed)
            // From the start, with the plan (instant answer).
            let e1 = js.decode(S.self, "(()=>{const r=solve(SB,newSim(SB),400);return {path:r.path,nodes:r.nodes,aborted:r.aborted,via:r.via}})()")
            let r1 = solve(lv, Sim(lv), cap: 400)
            XCTAssertEqual(r1.path, e1.path)
            XCTAssertEqual(r1.via, e1.via)
            // After two off-plan taps, without the plan: the depth-first search has to work it out.
            js.run("SB.plan=null;")
            lv.plan = nil
            let e2 = js.decode(S.self, """
            (()=>{const m=newSim(SB);settleTimed(SB,m);tap(SB,m.s,3);settleTimed(SB,m);tap(SB,m.s,2);settleTimed(SB,m);
              const r=solve(SB,m,400);return {path:r.path,nodes:r.nodes,aborted:r.aborted,via:r.via}})()
            """)
            var m = Sim(lv)
            settleTimed(lv, &m)
            tap(lv, &m.s, 3)
            settleTimed(lv, &m)
            tap(lv, &m.s, 2)
            settleTimed(lv, &m)
            let r2 = solve(lv, m, cap: 400)
            XCTAssertGreaterThan(e2.nodes, 1, "board \(i) should need a real search")
            XCTAssertEqual(r2.path, e2.path, "board \(i)")
            XCTAssertEqual(r2.nodes, e2.nodes, "board \(i)")
            XCTAssertEqual(r2.aborted, e2.aborted, "board \(i)")
        }
    }

    // MARK: - Game tools

    func testAcornDropAndRescue() {
        let lv = sharedBoard(29, "lv30", 30007)
        struct R: Decodable { var b: [Int]; var o: [Int]; var left: Int; var debt: [Int]; var sl: [[Int]]; var locked: Bool }
        let e = js.decode(R.self, """
        (()=>{const lv=SB,m=newSim(lv);tap(lv,m.s,0);tap(lv,m.s,1);
          for(const i of [0,41,820,1599,600,601,640])acornHit(lv,m.s,i);
          rescueSlots(lv,m.s,rngFrom(42),1);settleTimed(lv,m);
          return {b:Array.from(m.s.b),o:Array.from(m.s.o),left:m.s.left,debt:m.s.debt,sl:m.s.sl.map(n=>[n.c,n.r,n.id,n.k]),locked:m.s.locked}})()
        """)
        var m = Sim(lv)
        tap(lv, &m.s, 0)
        tap(lv, &m.s, 1)
        for i in [0, 41, 820, 1599, 600, 601, 640] { acornHit(lv, &m.s, i) }
        rescueSlots(lv, &m.s, RNG(seed: 42), 1)
        settleTimed(lv, &m)
        XCTAssertEqual(m.s.b.map(Int.init), e.b)
        XCTAssertEqual(m.s.o.map(Int.init), e.o)
        XCTAssertEqual(m.s.left, e.left)
        XCTAssertEqual(m.s.debt, e.debt)
        XCTAssertEqual(m.s.sl.map { [$0.c, $0.r, $0.id, $0.k] }, e.sl)
        XCTAssertEqual(m.s.locked, e.locked)
        XCTAssertLessThan(e.left, lv.art.total - 7, "the tools should have removed blocks")
    }

    /// How long a full in-game build takes in each engine (same work, same result).
    func testBuildSpeed() {
        let b = jsBase(99)
        var o = BuildOptions.game
        o.ms = 1e12
        let t0 = Date()
        let lv = generateLevel(base: b, seed: 100_007, diffKey: "lv100", options: o)
        let swiftMs = Date().timeIntervalSince(t0) * 1000
        let t1 = Date()
        let e = js.decode(LevelSummary?.self, "(()=>{const lv=generateLevel(testBase(99),100007,'lv100',{...BUILD_OPT_T,ms:1e12});return lv&&levelSummary(lv)})()".replacingOccurrences(of: "BUILD_OPT_T", with: "{seqs:2,iters:150,K:40,V:100,RV:300,CV:200,ms:4000}"))
        let jsMs = Date().timeIntervalSince(t1) * 1000
        XCTAssertEqual(lv?.summary, e)
        print(String(format: "BUILD SPEED board 100: Swift %.0f ms, JavaScript %.0f ms", swiftMs, jsMs))
    }
}
