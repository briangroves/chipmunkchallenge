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

// MARK: - Building a solution sequence

/// Nest size between the challenge's min and max, never leaving a leftover under 5 ants.
/// reach (nil = unlimited): when slots are nearly full, aim near what the nest can reach right now.
func pickSize(_ un: Int, _ def: Difficulty, _ rng: RNG, _ reach: Int?, _ relax: Bool) -> Int {
    let cap = reach.map { relax ? max($0, 1) : max($0, MIN_NEST) } ?? Int.max
    var s = (un <= def.cmax && Double(un) < Double(def.cmin) * 1.5) ? un : def.cmin + rng.int(def.cmax - def.cmin + 1)
    s = min(s, cap, un)
    let rem = un - s
    if rem > 0 && rem < MIN_NEST {
        if s + rem <= def.cmax && s + rem <= cap { s = un } else { s = max(min(MIN_NEST, un), s - (MIN_NEST - rem)) }
    } else if rem > 0 && rem < def.cmin && s + rem <= def.cmax && s + rem <= cap {
        s = un
    }
    return max(1, min(s, un))
}

/// Play the picture forward on the timed simulation, recording each nest opened. nil if the build jams.
func buildSequence(_ art: Art, _ def: Difficulty, _ rng: RNG, _ relax: Bool, _ pressure: Double) -> [NestSpec]? {
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
        let size = pickSize(un[col], def, rng, reach, relax)
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

/// Hill-climb over lane deals. Every candidate is solvable; keep the one whose model win rate is closest to target.
func tuneLanes(_ art: Art, _ def: Difficulty, _ seq: [NestSpec], _ seed: Int, _ opt: BuildOptions) -> Tuned {
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
        if let ct = def.ctarget { d += max(0, botRate(lv, max(16, opt.K >> 1), sd + 1, opt.eps) - ct) * 0.5 }
        if let cg = def.cgoal { d += abs(botRate(lv, max(24, opt.K), sd + 1, opt.eps) - cg) }
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
    let art = Art(rows: base.rows, rocks: base.rocks, lock: def.lock, slots: def.slots)
    for relax in [false, true] {
        var best: (seq: [NestSpec], tl: Tuned)?
        for k in 0..<opt.seqs {
            let rng = RNG(seed: baseSeed * 97 + k * 7919 + 13 + (relax ? 50000 : 0))
            let pr = def.pressure * (1 - Double(k) / Double(max(1, opt.seqs * 2)))
            var seq: [NestSpec]?
            var t = 0
            while t < 12 && seq == nil {
                seq = buildSequence(art, def, rng, relax, t < 6 ? pr : 0)
                t += 1
            }
            guard let seq else { continue }
            var tl = tuneLanes(art, def, seq, baseSeed * 31 + k, opt)
            // Judge each finished deal on games it was never tuned on.
            let chk = Level(art: art, slots: def.slots, lanes: lanesOf(seq, tl.a, def.lanes))
            let s1 = baseSeed * 7 + k * 31337
            tl.w = botRate(chk, opt.V, s1 + 1, 1)
            var d = (def.cgoal != nil ? 0.3 : 1) * abs(tl.w - def.rtarget)
            d += def.ctarget.map { max(0, botRate(chk, 60, s1 + 2, opt.eps) - $0) * 0.5 } ?? 0
            d += def.cgoal.map { abs(botRate(chk, 80, s1 + 2, opt.eps) - $0) } ?? 0
            tl.d = d
            if best == nil || tl.d < best!.tl.d { best = (seq, tl) }
        }
        guard let best else { continue }
        let seq = best.seq, tl = best.tl
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
        lv.botWin = botRate(lv, opt.CV ?? opt.V, baseSeed * 17 + 3, opt.eps)
        lv.randWin = botRate(lv, opt.RV ?? opt.V, baseSeed * 19 + 5, 1)
        lv.randN = opt.RV ?? opt.V
        lv.navSetup()
        /* Some pictures (few colours, big areas) come out far easier than their target whatever the deal. Rebuild those
           once with smaller nests (more, tighter decisions) and keep whichever lands closer to the target. */
        if let cg = def.cgoal, opt.scale == nil, lv.botWin! > cg + 0.15 {
            var bestLv = lv
            func closer(_ x: Level?) -> Bool {
                guard let x else { return false }
                return abs(x.botWin! - cg) < abs(bestLv.botWin! - cg)
            }
            var o2 = opt
            o2.scale = 0.65
            let lv2 = generateLevel(base: base, seed: baseSeed, diffKey: diffKey, options: o2)
            if closer(lv2) { bestLv = lv2! }
            /* Still far too easy, and the locked slot is already part of the game by this board: try it with a lock. */
            if bestLv.botWin! > cg + 0.15 && base.lockOK && !def.lock {
                var b3 = base
                b3.lock = true
                let lv3 = generateLevel(base: b3, seed: baseSeed, diffKey: diffKey, options: o2)
                if closer(lv3) { bestLv = lv3! }
            }
            return bestLv
        }
        return lv
    }
    return nil
}
