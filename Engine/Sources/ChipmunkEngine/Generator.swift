import Foundation

/* ================= LEVEL BUILDING AND DIFFICULTY =================
   1. buildSequence plays the picture forward on the timed simulation and records every nest it opens.
      Tapping nests in that order always clears the board, so it is a guaranteed solution.
   2. Any way of dealing those nests into lanes, keeping their order inside each lane, stays solvable.
   3. tuneLanes searches over those deals with a player model, keeping changes that move the model's win rate
      toward the challenge target. The puzzle gets harder without ever becoming unsolvable. */

// MARK: - Player model on the fast (instant-eating) model

/// A careful player taps a front nest whose color is already exposed, preferring nests that can finish.
/// eps = share of thoughtless taps (1 = a random tapper).
func botPick(_ lv: Level, _ s: State, _ rng: RNG, _ eps: Double) -> Int {
    let mv = legalMoves(lv, s)
    if mv.isEmpty { return -1 }
    if rng.next() < eps { return mv[rng.int(mv.count)] }
    var best = -1
    var bs = -1.0
    for l in mv {
        let n = lv.lanes[l][s.lp[l]], reach = s.hp[n.c].count
        let base: Double = reach >= n.n ? 2 : reach > 0 ? 1 + 0.5 * Double(reach) / Double(n.n) : 0
        let sc = base + rng.next() * 0.35
        if sc > bs {
            bs = sc
            best = l
        }
    }
    return best
}

func botPlay(_ lv: Level, _ s0: State, _ rng: RNG, _ eps: Double) -> Bool {
    var s = s0
    settleAll(lv, &s)
    while true {
        if s.left == 0 { return true }
        let l = botPick(lv, s, rng, eps)
        if l < 0 { return false }
        tap(lv, &s, l)
        settleAll(lv, &s)
    }
}

/// Share of `n` games the player model wins.
public func botRate(_ lv: Level, _ n: Int, _ seed: Int, _ eps: Double = 0.1) -> Double {
    let s0 = initState(lv)
    var w = 0
    for i in 0..<n where botPlay(lv, s0, RNG(seed: seed + i * 7919), eps) { w += 1 }
    return Double(w) / Double(n)
}

// MARK: - The native game's careful player (since 2026-11-21)

/* The web game's careful player (botPick) looks only at the front nests and slips one tap in ten, and the builder judged
   boards with it on the instant-eating model. Measured on the timed game, a player who simply avoids taps that leave no
   move won 0.40-0.52 on boards built for 0.20-0.35, so the hard end of the ramp played far easier than its goal. The
   native builder judges with this stronger player, and judges finished boards on the timed game. */

/// Share of thoughtless taps for the native careful player (the web game's is 0.1).
public let CAREFUL_EPS = 0.05

/// The native careful player: a random tap `eps` of the time; otherwise it looks one tap ahead and never takes a tap
/// that leaves no move when another doesn't, and among the rest prefers nests that can finish (as `botPick`).
func carefulPick(_ lv: Level, _ s: State, _ rng: RNG, _ eps: Double) -> Int {
    let mv = legalMoves(lv, s)
    if mv.isEmpty { return -1 }
    if rng.next() < eps { return mv[rng.int(mv.count)] }
    var best = -1
    var bs = -Double.infinity
    for l in mv {
        let n = lv.lanes[l][s.lp[l]], reach = s.hp[n.c].count
        var sc: Double = (reach >= n.n ? 2 : reach > 0 ? 1 + 0.5 * Double(reach) / Double(n.n) : 0) + rng.next() * 0.35
        var s2 = s
        tap(lv, &s2, l)
        settleAll(lv, &s2)
        if s2.left > 0 && legalMoves(lv, s2).isEmpty { sc -= 100 }
        if sc > bs {
            bs = sc
            best = l
        }
    }
    return best
}

/// One game by the native careful player, on the instant model or (timed) the game's own timing, tapping whenever the
/// board is idle.
func carefulPlay(_ lv: Level, _ rng: RNG, _ eps: Double, timed: Bool) -> Bool {
    if !timed {
        var s = initState(lv)
        settleAll(lv, &s)
        while true {
            if s.left == 0 { return true }
            let l = carefulPick(lv, s, rng, eps)
            if l < 0 { return false }
            tap(lv, &s, l)
            settleAll(lv, &s)
        }
    }
    var m = Sim(lv)
    settleTimed(lv, &m)
    while true {
        if m.s.left == 0 { return true }
        let l = carefulPick(lv, m.s, rng, eps)
        if l < 0 { return false }
        tap(lv, &m.s, l)
        settleTimed(lv, &m)
    }
}

/// Share of `n` games the native careful player wins. Timed play needs the level's navigation (`navSetup`). Timed
/// games are slow (10-40 ms each), so they run in parallel, each thread on its own copy of the level (routing borrows
/// scratch buffers stored on it); each game has its own seed, so the result doesn't depend on the threads.
public func carefulRate(_ lv: Level, _ n: Int, _ seed: Int, _ eps: Double = CAREFUL_EPS, timed: Bool) -> Double {
    guard n > 0 else { return 0 }
    if !timed {
        var w = 0
        for i in 0..<n where carefulPlay(lv, RNG(seed: seed + i * 7919), eps, timed: false) { w += 1 }
        return Double(w) / Double(n)
    }
    let workers = max(1, min(n, ProcessInfo.processInfo.activeProcessorCount))
    let copies = (0..<workers).map { _ in lv.copy() }
    let wins = UnsafeMutableBufferPointer<Int>.allocate(capacity: workers)
    defer { wins.deallocate() }
    DispatchQueue.concurrentPerform(iterations: workers) { w in
        var c = 0
        for i in stride(from: w, to: n, by: workers) where carefulPlay(copies[w], RNG(seed: seed + i * 7919), eps, timed: true) {
            c += 1
        }
        wins[w] = c
    }
    return Double(wins.reduce(0, +)) / Double(n)
}

// MARK: - Building a solution sequence

/// Nest size between the challenge's min and max, never leaving a leftover under 5 ants.
/// reach (nil = unlimited): when slots are nearly full, aim near what the nest can reach right now.
/// `webParity` keeps the web game's rule, which could leave a last nest under 5 when the reach cap stopped the
/// remainder from joining (the native game takes those blocks whole instead, since 2026-11-13).
/// `floor` is the smallest nest a relaxed build may make (the native game relaxes to 3 first and to 1 only if that
/// still jams); nil means the web game's relaxed rule (floor 1).
func pickSize(_ un: Int, _ def: Difficulty, _ rng: RNG, _ reach: Int?, _ relax: Bool, webParity: Bool = false,
              floor: Int? = nil) -> Int {
    let lo = relax ? (webParity ? 1 : floor ?? 1) : MIN_NEST
    let cap = reach.map { max($0, lo) } ?? Int.max
    var s = (un <= def.cmax && Double(un) < Double(def.cmin) * 1.5) ? un : def.cmin + rng.int(def.cmax - def.cmin + 1)
    s = min(s, cap, un)
    let rem = un - s
    if rem > 0 && rem < MIN_NEST {
        if s + rem <= def.cmax && s + rem <= cap { s = un }
        // Too few left to split into two nests of 5 or more: take them all rather than leave a nest under 5 (unless
        // the build is already relaxed to get unstuck).
        else if !relax && !webParity && un < 2 * MIN_NEST { s = un }
        // Relaxed to a floor above 1: neither this nest nor what it leaves may go under the floor. Leave 5 if this
        // nest can still be at least the floor, else keep a remainder that is already at the floor, else split so
        // the remainder is exactly the floor, else take the whole remainder now (it joins this nest).
        else if relax && !webParity && lo > 1 {
            if s - (MIN_NEST - rem) >= lo { s -= MIN_NEST - rem }
            else if rem >= lo {}
            else if un - lo >= lo { s = un - lo }
            else { s = un }
        }
        else { s = max(min(MIN_NEST, un), s - (MIN_NEST - rem)) }
    } else if rem > 0 && rem < def.cmin && s + rem <= def.cmax && s + rem <= cap {
        s = un
    }
    return max(1, min(s, un))
}

/// Play the picture forward on the timed simulation, recording each nest opened. nil if the build jams.
func buildSequence(_ art: Art, _ def: Difficulty, _ rng: RNG, _ relax: Bool, _ pressure: Double,
                   webParity: Bool = false, floor: Int? = nil) -> [NestSpec]? {
    let lv = Level(art: art, slots: def.slots, lanes: [])
    lv.navSetup()
    var m = Sim(lv)
    var un = art.counts
    var seq: [NestSpec] = []
    let keyAt = art.lock ? 2 + rng.int(3) : -1   // locked slot: the 3rd-5th nest carries the key
    while true {
        settleTimed(lv, &m)
        if un.allSatisfy({ $0 == 0 }) { return seq }
        var cands: [Int] = []
        for c in 1..<un.count where un[c] > 0 && !m.s.hp[c].isEmpty { cands.append(c) }
        if cands.isEmpty || !canTap(lv, m.s) { return nil }
        // Relaxed to a floor above 1 with the slots nearly full: open a color with at least the floor in reach when
        // there is one, so the nest can finish without going under the floor.
        if relax && !webParity, let f = floor, f > 1, lv.slots - m.s.sl.count <= 2 {
            let ok = cands.filter { m.s.hp[$0].count >= f }
            if !ok.isEmpty { cands = ok }
        }
        let col: Int
        if pressure > 0 && rng.next() < pressure {
            var tw = 0.0
            let w = cands.map { c -> Double in
                let x = 1 / Double(m.s.hp[c].count + 1)
                tw += x
                return x
            }
            var q = rng.next() * tw
            var k = 0
            while k < w.count && q > w[k] {
                q -= w[k]
                k += 1
            }
            col = cands[min(k, cands.count - 1)]
        } else {
            col = cands[rng.int(cands.count)]
        }
        let reach: Int? = lv.slots - m.s.sl.count <= 2 ? m.s.hp[col].count : nil
        let size = pickSize(un[col], def, rng, reach, relax, webParity: webParity, floor: floor)
        un[col] -= size
        let key = seq.count == keyAt
        seq.append(NestSpec(c: col, n: size, key: key))
        addNest(lv, &m.s, col, size, key)
    }
}

// MARK: - Dealing the sequence into lanes

func lanesOf(_ seq: [NestSpec], _ a: [Int], _ L: Int) -> [[NestSpec]] {
    var lanes = Array(repeating: [NestSpec](), count: L)
    for (j, n) in seq.enumerated() { lanes[a[j]].append(n) }
    return lanes
}

func balanced(_ a: [Int], _ L: Int) -> Bool {
    var cnt = Array(repeating: 0, count: L)
    for x in a { cnt[x] += 1 }
    let avg = Double(a.count) / Double(L)
    return cnt.allSatisfy { $0 > 0 && Double($0) >= avg * 0.6 && Double($0) <= avg * 1.4 }
}

/// Options for one board build (JS generateLevel's `opt`).
public struct BuildOptions: Sendable {
    public var seqs = 3
    public var iters = 60
    public var K = 40
    public var V = 120
    public var eps = 0.1
    /// Time budget for each lane tuning, in milliseconds.
    public var ms: Double = 2500
    public var scale: Double?
    /// The player's own 💪 target (tailoring).
    public var aim: Double?
    public var CV: Int?
    public var RV: Int?
    /// Build exactly as the web game does (tests comparing the two); the game leaves it off.
    public var webParity = false
    /// Native: timed games by the careful player to judge each deal, and to measure the finished board (`botWin`).
    public var judgeN = 32
    public var timedCV = 80
    /// Native: the timed-vs-fast-model gap already learned on this picture (passed to the too-easy rebuilds).
    var gapHint: Double?
    /// Native: this build is the one extra try for a board that came out far too hard.
    var rescue = false

    public init() {}

    /// What the game uses: a few seconds per board.
    public static var game: BuildOptions {
        var o = BuildOptions()
        o.seqs = 2
        o.iters = 150
        o.K = 40
        o.V = 100
        o.RV = 300
        o.CV = 200
        o.ms = 4000
        return o
    }
}

struct Tuned {
    var a: [Int]
    var w: Double
    var d: Double
    var it: Int
}

/// Native: how far a careful player's win rate `w` misses the goal. Too hard counts 1.5 times too easy: a board must
/// never feel impossible.
func goalMiss(_ w: Double, _ cg: Double) -> Double { w < cg ? 1.5 * (cg - w) : w - cg }

/// Native: a board whose careful player wins less than this is far too hard for its goal.
func hardFloor(_ cg: Double) -> Double { max(0.03, cg * 0.4) }

/// Hill-climb over lane deals. Every candidate is solvable; keep the one whose model win rate is closest to target.
/// The native game climbs with the same fast player, but aims at `aimGoal` in place of the challenge's goal: the goal
/// corrected for how far the native careful player on the timed game differs from this fast model on this picture.
func tuneLanes(_ art: Art, _ def: Difficulty, _ seq: [NestSpec], _ seed: Int, _ opt: BuildOptions,
               aimGoal: Double? = nil) -> Tuned {
    let L = def.lanes, rng = RNG(seed: seed)
    let lv = Level(art: art, slots: def.slots, lanes: [])
    var a: [Int]
    repeat { a = seq.map { _ in rng.int(L) } } while !balanced(a, L)
    var epoch = 0
    func score(_ a: [Int]) -> (w: Double, d: Double) {
        lv.lanes = lanesOf(seq, a, L)
        let sd = seed * 13 + 5 + epoch * 104_729
        let w = botRate(lv, opt.K, sd, 1)
        var d = def.cgoal != nil ? 0.3 * abs(w - def.rtarget) : abs(w - def.rtarget)
        func care(_ n: Int) -> Double { botRate(lv, n, sd + 1, opt.eps) }
        if let ct = def.ctarget { d += max(0, care(max(16, opt.K >> 1)) - ct) * 0.5 }
        if let cg = aimGoal ?? def.cgoal { d += abs(care(max(24, opt.K)) - cg) }
        return (w, d)
    }
    var cur = score(a)
    var it = 0
    let t0 = Date()
    while it < opt.iters && Date().timeIntervalSince(t0) * 1000 < opt.ms {
        it += 1
        if it % 15 == 0 {
            epoch += 1
            cur = score(a)
        }
        var b = a
        if rng.next() < 0.5 {
            let k = 1 + rng.int(3)
            for _ in 0..<k {
                let idx = rng.int(b.count)
                b[idx] = rng.int(L)
            }
        } else {
            let i = rng.int(b.count), j = rng.int(b.count)
            b.swapAt(i, j)
        }
        if !balanced(b, L) { continue }
        let nx = score(b)
        if nx.d <= cur.d {
            a = b
            cur = nx
        }
    }
    return Tuned(a: a, w: cur.w, d: cur.d, it: it)
}

// MARK: - Building a board

/// Build a solvable board from a picture, tuned to the challenge `diffKey`. nil when the picture can't make one.
public func generateLevel(base: LevelBase, seed baseSeed: Int, diffKey: String = "normal",
                          options: BuildOptions = BuildOptions()) -> Level? {
    let opt = options
    var def = Difficulty.named(diffKey)
    def.lock = base.lock
    if let scale = opt.scale {
        def.cmin = max(MIN_NEST, JS.roundInt(Double(def.cmin) * scale))
        def.cmax = max(def.cmin + 4, JS.roundInt(Double(def.cmax) * scale))
        def.pressure = 1
    }
    if let aim = opt.aim, aim != 0 {
        let t = aim * def.rtarget   // the player's tailoring factor (1 = standard)
        def.rtarget = 1 / aim
        if let ct = def.ctarget { def.ctarget = min(0.75, max(0.08, ct / t)) }
        if let cg = def.cgoal, t != 1 { def.cgoal = min(0.98, max(0.05, pow(cg, t))) }
    }
    let art = Art(rows: base.rows, rocks: base.rocks, water: base.water, burrows: base.burrows, lock: def.lock,
                  slots: def.slots)
    /* Passes: strict (nests of 5 or more), then relaxed when the strict build jams. The web game relaxes straight to
       nests of 1; the native game first relaxes only to 3 (so a nest under 3 appears only when even that jams, or a
       color has fewer than 3 blocks), on the same seeds the old single relaxed pass used. */
    let passes: [(relax: Bool, floor: Int?)] = opt.webParity ? [(false, nil), (true, nil)]
        : [(false, nil), (true, 3), (true, 1)]
    for (relax, floor) in passes {
        var best: (seq: [NestSpec], tl: Tuned)?
        // Native: how much easier the timed game plays than the instant model on this picture, learned from each deal
        // and used to aim the next one.
        var gap = opt.gapHint ?? 0, bestGap = gap
        for k in 0..<opt.seqs {
            let rng = RNG(seed: baseSeed * 97 + k * 7919 + 13 + (relax ? 50000 : 0))
            let pr = def.pressure * (1 - Double(k) / Double(max(1, opt.seqs * 2)))
            var seq: [NestSpec]?
            var t = 0
            while t < 12 && seq == nil {
                seq = buildSequence(art, def, rng, relax, t < 6 ? pr : 0, webParity: opt.webParity, floor: floor)
                t += 1
            }
            guard let seq else { continue }
            let aimGoal = opt.webParity ? nil : def.cgoal.map { min(0.99, max(0.01, $0 - gap)) }
            var tl = tuneLanes(art, def, seq, baseSeed * 31 + k, opt, aimGoal: aimGoal)
            // Judge each finished deal on games it was never tuned on (the native game: on the timed game).
            let chk = Level(art: art, slots: def.slots, lanes: lanesOf(seq, tl.a, def.lanes))
            let s1 = baseSeed * 7 + k * 31337
            tl.w = botRate(chk, opt.V, s1 + 1, 1)
            var d = (def.cgoal != nil ? 0.3 : 1) * abs(tl.w - def.rtarget)
            if opt.webParity {
                d += def.ctarget.map { max(0, botRate(chk, 60, s1 + 2, opt.eps) - $0) * 0.5 } ?? 0
                d += def.cgoal.map { abs(botRate(chk, 80, s1 + 2, opt.eps) - $0) } ?? 0
            } else if def.ctarget != nil || def.cgoal != nil {
                chk.navSetup()
                let wt = carefulRate(chk, opt.judgeN, s1 + 2, timed: true)
                // A deal the fast model rates fine can lose almost every timed game; keep one such deal from swinging
                // the next deal's aim too far.
                gap = min(0.3, max(-0.3, wt - botRate(chk, 120, s1 + 2, opt.eps)))
                d += def.ctarget.map { max(0, wt - $0) * 0.5 } ?? 0
                d += def.cgoal.map { goalMiss(wt, $0) } ?? 0
            }
            tl.d = d
            if best == nil || tl.d < best!.tl.d { best = (seq, tl); bestGap = gap }
        }
        guard let best else { continue }
        let seq = best.seq, tl = best.tl, lastGap = bestGap
        let lv = Level(art: art, slots: def.slots, lanes: lanesOf(seq, tl.a, def.lanes))
        lv.def = def
        lv.diff = diffKey
        lv.seed = baseSeed
        lv.plan = tl.a
        lv.nests = seq.count
        lv.small = seq.filter { $0.n < MIN_NEST }.count
        lv.minNest = seq.map(\.n).min()
        lv.maxNest = seq.map(\.n).max()
        lv.tuneIters = tl.it
        lv.aim = opt.aim
        if opt.webParity {
            lv.botWin = botRate(lv, opt.CV ?? opt.V, baseSeed * 17 + 3, opt.eps)
            lv.randWin = botRate(lv, opt.RV ?? opt.V, baseSeed * 19 + 5, 1)
            lv.navSetup()
        } else {
            lv.navSetup()
            lv.botWin = carefulRate(lv, opt.timedCV, baseSeed * 17 + 3, timed: true)
            lv.randWin = botRate(lv, opt.RV ?? opt.V, baseSeed * 19 + 5, 1)
        }
        lv.randN = opt.RV ?? opt.V
        /* Some pictures (few colours, big areas) come out far easier than their target whatever the deal. Rebuild those
           with smaller nests (more, tighter decisions) and keep whichever lands closer to the target. The native game
           rebuilds when a board is 0.08 too easy (the web game: 0.15), and tries even smaller nests if that's not
           enough. */
        let tooEasy = opt.webParity ? 0.15 : 0.08
        if let cg = def.cgoal, opt.scale == nil, lv.botWin! > cg + tooEasy {
            var bestLv = lv
            func closer(_ x: Level?) -> Bool {
                guard let x else { return false }
                if opt.webParity { return abs(x.botWin! - cg) < abs(bestLv.botWin! - cg) }
                // Never trade a too-easy board for one that's far too hard.
                return x.botWin! >= hardFloor(cg) && goalMiss(x.botWin!, cg) < goalMiss(bestLv.botWin!, cg)
            }
            var o2 = opt
            o2.scale = 0.65
            if !opt.webParity {
                // Rebuilds start from the gap this picture already showed, and deal once with half the search (a
                // phone builds the board while the intro plays).
                o2.gapHint = lastGap
                o2.iters = max(40, opt.iters / 2)
                o2.seqs = 1
                o2.timedCV = max(24, opt.timedCV / 2)
            }
            let lv2 = generateLevel(base: base, seed: baseSeed, diffKey: diffKey, options: o2)
            if closer(lv2) { bestLv = lv2! }
            /* Still far too easy, and the locked slot is already part of the game by this board: try it with a lock. */
            if bestLv.botWin! > cg + tooEasy && base.lockOK && !def.lock {
                var b3 = base
                b3.lock = true
                let lv3 = generateLevel(base: b3, seed: baseSeed, diffKey: diffKey, options: o2)
                if closer(lv3) { bestLv = lv3! }
            }
            /* Native: still too easy, so halve the nests (keeping the lock if that's what helped). */
            if !opt.webParity && bestLv.botWin! > cg + tooEasy {
                var o3 = o2
                o3.scale = 0.5
                var b4 = base
                b4.lock = bestLv.lock
                let lv4 = generateLevel(base: b4, seed: baseSeed, diffKey: diffKey, options: o3)
                if closer(lv4) { bestLv = lv4! }
            }
            return bestLv
        }
        /* Native: far too hard (some deals that the fast model rates fine lose almost every timed game): one more
           build on another seed, kept if it lands closer. */
        if !opt.webParity, let cg = def.cgoal, opt.scale == nil, !opt.rescue, lv.botWin! < hardFloor(cg) {
            var o5 = opt
            o5.rescue = true
            if let lv5 = generateLevel(base: base, seed: baseSeed + 7_777, diffKey: diffKey, options: o5),
               goalMiss(lv5.botWin!, cg) < goalMiss(lv.botWin!, cg) {
                return lv5
            }
        }
        return lv
    }
    return nil
}

/// `generateLevel`, but if this seed can't make a board, try a few others before giving up. A handful of the clipart
/// pictures fail on one seed and build on the next; without this the player would be stuck on "couldn't build".
/// The extra seeds are far from the per-attempt seeds (seed + attempt), so a retry never repeats another attempt.
public func generateLevelRetrying(base: LevelBase, seed: Int, diffKey: String = "normal",
                                  options: BuildOptions = BuildOptions(), tries: Int = 6) -> Level? {
    for k in 0..<max(1, tries) {
        if let lv = generateLevel(base: base, seed: seed + k * 100_003, diffKey: diffKey, options: options) {
            return lv
        }
    }
    return nil
}
