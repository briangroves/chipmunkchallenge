import Foundation

/// A nest sitting in a holding slot: `r` critters of color `c` still to send. `k` is the slot it occupies (which
/// decides its exit hole). `w`: a magic nest whose critters fly. `key`: finishing it opens the locked slot.
public struct Slot: Equatable, Hashable, Sendable {
    public var c: Int
    public var r: Int
    public var id: Int
    public var k: Int
    public var w: Bool = false
    public var key: Bool = false
}

/// Everything that changes during a board. A value type, so copying it is the JS `clone`.
public struct State: Sendable {
    /// Color per cell (0 once eaten).
    public internal(set) var b: [UInt8]
    /// Empty cell connected to the outside.
    public internal(set) var o: [UInt8]
    /// Block that has been exposed (and pushed onto its color's heap).
    var ed: [UInt8]
    /// Block reserved by a critter on its way.
    public internal(set) var cl: [UInt8]
    /// Per color: min-heap of edible, unclaimed blocks ordered by pickup key. May hold stale entries after magic.
    var hp: [[Int]]
    /// Per lane: index of the front nest.
    public internal(set) var lp: [Int]
    /// Per lane: nests already pulled out of the middle by a magic wand.
    public internal(set) var tk: [[UInt8]]
    /// Nests in the holding slots, in the order they were placed.
    public internal(set) var sl: [Slot]
    /// Blocks of each color removed outside the nests (Acorn Drop) that no nest has accounted for yet.
    public internal(set) var debt: [Int]
    /// Blocks left on the board (rocks not counted).
    public internal(set) var left: Int
    var nid: Int
    /// The rightmost slot is locked until the key nest finishes.
    public internal(set) var locked: Bool
    /// Navigation: an ant can stand here / how many of the 8 surrounding cells are wall or solid.
    var hasNav = false
    var pass: [UInt8] = []
    var wn: [Int] = []

    /// Blocks of color `col` a critter could reach right now (the JS `s.hp[col].length`).
    public func reach(_ col: Int) -> Int { hp[col].count }
    public var won: Bool { left == 0 }
}

// MARK: - Heaps

@inline(__always) func hpush(_ h: inout [Int], _ v: Int, _ K: [Int]) {
    h.append(v)
    var i = h.count - 1
    let kv = K[v]
    while i > 0 {
        let p = (i - 1) >> 1
        if K[h[p]] <= kv { break }
        h[i] = h[p]
        i = p
    }
    h[i] = v
}

@inline(__always) func hpop(_ h: inout [Int], _ K: [Int]) -> Int? {
    guard let top = h.first else { return nil }
    let last = h.removeLast()
    let n = h.count
    if n > 0 {
        var i = 0
        let kl = K[last]
        while true {
            var l = 2 * i + 1
            if l >= n { break }
            let r = l + 1
            if r < n && K[h[r]] < K[h[l]] { l = r }
            if K[h[l]] >= kl { break }
            h[i] = h[l]
            i = l
        }
        h[i] = last
    }
    return top
}

// MARK: - Exposure

/// A block is edible when any face touches open space: the board's outer edge, or an empty cell connected to it.
@inline(__always) func onEdge(_ lv: Level, _ i: Int) -> Bool {
    let r = i / lv.W, c = i % lv.W
    return r == 0 || r == lv.H - 1 || c == 0 || c == lv.W - 1
}

func openFrom(_ lv: Level, _ s: inout State, _ seeds: [Int]) {
    let W = lv.W, H = lv.H, key = lv.art.key
    var q = seeds
    while let i = q.popLast() {
        let r = i / W, c = i % W
        for k in 0..<4 {
            let j: Int
            if k == 0 { if r == 0 { continue }; j = i - W }
            else if k == 1 { if r == H - 1 { continue }; j = i + W }
            else if k == 2 { if c == 0 { continue }; j = i - 1 }
            else { if c == W - 1 { continue }; j = i + 1 }
            let bj = s.b[j]
            if bj != 0 {
                if bj != ROCK && s.ed[j] == 0 {
                    s.ed[j] = 1
                    hpush(&s.hp[Int(bj)], j, key)
                }
            } else if s.o[j] == 0 {
                s.o[j] = 1
                openNav(lv, &s, j)
                q.append(j)
            }
        }
    }
}

public func initState(_ lv: Level) -> State {
    let n = lv.W * lv.H
    var s = State(b: lv.art.cells, o: [UInt8](repeating: 0, count: n), ed: [UInt8](repeating: 0, count: n),
                  cl: [UInt8](repeating: 0, count: n), hp: Array(repeating: [], count: lv.art.chars.count + 1),
                  lp: Array(repeating: 0, count: lv.lanes.count),
                  tk: lv.lanes.map { [UInt8](repeating: 0, count: $0.count) }, sl: [],
                  debt: Array(repeating: 0, count: lv.art.chars.count + 1), left: lv.art.total, nid: 0,
                  locked: lv.lock)
    var seeds: [Int] = []
    let key = lv.art.key
    for i in 0..<n {
        if !onEdge(lv, i) { continue }
        let bi = s.b[i]
        if bi != 0 {
            if bi != ROCK && s.ed[i] == 0 {
                s.ed[i] = 1
                hpush(&s.hp[Int(bi)], i, key)
            }
        } else if s.o[i] == 0 {
            s.o[i] = 1
            seeds.append(i)
        }
    }
    openFrom(lv, &s, seeds)
    if lv.hasNav { initNav(lv, &s) }
    return s
}

public func findEdible(_ lv: Level, _ s: State, _ col: Int) -> Int {
    s.hp[col].first ?? -1
}

/// An ant leaving the nest reserves a block. The block stays solid: nobody else can claim it, ants cannot walk
/// through it, and nothing behind it opens up yet.
func claim(_ lv: Level, _ s: inout State, _ col: Int) -> Int {
    while true {
        guard let i = hpop(&s.hp[col], lv.art.key) else { return -1 }
        if Int(s.b[i]) == col && s.cl[i] == 0 {
            s.cl[i] = 1
            return i
        }
    }
}

/// Heaps can hold stale entries once a magic critter has taken a block out of turn: drop them before asking.
func hasEdible(_ lv: Level, _ s: inout State, _ col: Int) -> Bool {
    while let top = s.hp[col].first, Int(s.b[top]) != col || s.cl[top] != 0 {
        _ = hpop(&s.hp[col], lv.art.key)
    }
    return !s.hp[col].isEmpty
}

// MARK: - Magic wand
/* A magic nest's critters fly in a straight line, over anything in the way, to the nearest remaining block of their
   color (same pickup order), buried or not, and fly straight back to the drain. A block taken from inside the picture
   leaves a sealed hole; it joins the open space only once the outside reaches it. */

func magicPick(_ lv: Level, _ s: State, _ col: Int) -> Int {
    for i in lv.colorOrder(col) where Int(s.b[i]) == col && s.cl[i] == 0 { return i }
    return -1
}

func claimMagic(_ lv: Level, _ s: inout State, _ col: Int) -> Int {
    let i = magicPick(lv, s, col)
    if i >= 0 { s.cl[i] = 1 }
    return i
}

func removeMagic(_ lv: Level, _ s: inout State, _ i: Int) {
    let W = lv.W, H = lv.H, r = i / W, c = i % W
    let open = onEdge(lv, i)
        || (r > 0 && s.b[i - W] == 0 && s.o[i - W] != 0)
        || (r < H - 1 && s.b[i + W] == 0 && s.o[i + W] != 0)
        || (c > 0 && s.b[i - 1] == 0 && s.o[i - 1] != 0)
        || (c < W - 1 && s.b[i + 1] == 0 && s.o[i + 1] != 0)
    if open {
        removeBlock(lv, &s, i)
        return
    }
    s.b[i] = 0
    s.left -= 1
}

/// The ant has reached the block and picked it up. Only now does the space open.
func removeBlock(_ lv: Level, _ s: inout State, _ i: Int) {
    s.b[i] = 0
    s.left -= 1
    s.o[i] = 1
    openNav(lv, &s, i)
    openFrom(lv, &s, [i])
}

/// A nest finished (its last critter left, or it needed nothing): if it carried the key, the locked slot opens.
@inline(__always) func nestDone(_ s: inout State, _ n: Slot) {
    if n.key { s.locked = false }
}

func canFeed(_ lv: Level, _ s: inout State, _ n: Slot) -> Bool {
    n.w ? magicPick(lv, s, n.c) >= 0 : hasEdible(lv, &s, n.c)
}

/// Instant eating (the fast model the bots and builder use). Returns the block taken, or -1.
func eat(_ lv: Level, _ s: inout State, _ col: Int) -> Int {
    let i = claim(lv, &s, col)
    // JS would run removeBlock(-1) here; that only happens with stale heap entries, which the fast model never has.
    if i >= 0 { removeBlock(lv, &s, i) }
    return i
}

// MARK: - Fast model: rounds

public struct Bite: Equatable, Sendable {
    public var i: Int
    public var c: Int
    public var id: Int
}

/// One round: every nest in a slot (in the order they were placed) sends one ant. `gate` lets a caller hold a nest
/// back. With `deferred` the block is only claimed. The bots pass neither and remove instantly.
@discardableResult
func settleRound(_ lv: Level, _ s: inout State, out: ((Bite) -> Void)? = nil,
                 gate: ((Slot) -> Bool)? = nil, deferred: Bool = false) -> Bool {
    var p = false
    var k = 0
    while k < s.sl.count {
        let n = s.sl[k]
        if s.hp[n.c].isEmpty || (gate.map { !$0(n) } ?? false) {
            k += 1
            continue
        }
        let i = deferred ? claim(lv, &s, n.c) : eat(lv, &s, n.c)
        out?(Bite(i: i, c: n.c, id: n.id))
        s.sl[k].r -= 1
        p = true
        if s.sl[k].r == 0 {
            let done = s.sl.remove(at: k)
            nestDone(&s, done)
        } else {
            k += 1
        }
    }
    return p
}

func settleAll(_ lv: Level, _ s: inout State) {
    while settleRound(lv, &s) {}
}

// MARK: - Tapping

public func canTap(_ lv: Level, _ s: State) -> Bool {
    s.sl.count < lv.slots - (s.locked ? 1 : 0)
}

public func legalMoves(_ lv: Level, _ s: State) -> [Int] {
    if !canTap(lv, s) { return [] }
    var m: [Int] = []
    for l in lv.lanes.indices where s.lp[l] < lv.lanes[l].count { m.append(l) }
    return m
}

/// A nest takes the leftmost free slot; its slot decides which exit hole its ants use. Returns the new nest's id,
/// or 0 when Acorn Drop debt already covered it.
@discardableResult
func addNest(_ lv: Level, _ s: inout State, _ c: Int, _ r0: Int, _ key: Bool) -> Int {
    var r = r0
    if s.debt[c] > 0 {
        let t = min(s.debt[c], r)
        s.debt[c] -= t
        r -= t
        if r <= 0 {
            if key { s.locked = false }
            return 0
        }
    }
    var used = Set(s.sl.map(\.k))
    if s.locked { used.insert(lv.lockAt) }
    var k = 0
    while used.contains(k) { k += 1 }
    s.nid += 1
    s.sl.append(Slot(c: c, r: r, id: s.nid, k: k, key: key))
    return s.nid
}

/// Tap lane `l`: its front nest moves into a slot.
@discardableResult
public func tap(_ lv: Level, _ s: inout State, _ l: Int) -> Int {
    let n = lv.lanes[l][s.lp[l]]
    s.lp[l] += 1
    skipTaken(lv, &s, l)
    return addNest(lv, &s, n.c, n.n, n.key)
}

/// A magic wand can pull a nest out of the middle of a column. The column's front then skips over it.
func skipTaken(_ lv: Level, _ s: inout State, _ l: Int) {
    while s.lp[l] < lv.lanes[l].count && s.tk[l][s.lp[l]] != 0 { s.lp[l] += 1 }
}

@discardableResult
public func tapAt(_ lv: Level, _ s: inout State, _ l: Int, _ i: Int) -> Int {
    if i <= s.lp[l] { return tap(lv, &s, l) }
    let n = lv.lanes[l][i]
    s.tk[l][i] = 1
    return addNest(lv, &s, n.c, n.n, n.key)
}

/// Mark the nest with id `id` as magic (its critters fly).
public func makeMagic(_ s: inout State, id: Int) {
    if let k = s.sl.firstIndex(where: { $0.id == id }) { s.sl[k].w = true }
}

// MARK: - Tools

/// Acorn Drop: an acorn lands on board cell i and knocks out that one block (not one a critter is already fetching).
/// A nest of that colour sitting in a slot needs one block fewer; if none is, the next nest of that colour will.
@discardableResult
public func acornHit(_ lv: Level, _ s: inout State, _ i: Int) -> Bool {
    let c = Int(s.b[i])
    if c == 0 || c == Int(ROCK) || s.cl[i] != 0 { return false }
    /* Only a block on the edge of the open area opens a path. A buried one leaves a sealed hole. */
    let W = lv.W, H = lv.H, r = i / W, cc = i % W
    let reach = onEdge(lv, i) || (r > 0 && s.o[i - W] != 0) || (r < H - 1 && s.o[i + W] != 0)
        || (cc > 0 && s.o[i - 1] != 0) || (cc < W - 1 && s.o[i + 1] != 0)
    if reach {
        removeBlock(lv, &s, i)
    } else {
        s.b[i] = 0
        s.left -= 1
    }
    if let k = s.sl.firstIndex(where: { $0.c == c && $0.r > 0 }) {
        s.sl[k].r -= 1
        if s.sl[k].r == 0 {
            let n = s.sl.remove(at: k)
            nestDone(&s, n)
        }
    } else {
        s.debt[c] += 1
    }
    return true
}

/// Continue after getting stuck: empty up to `count` slots chosen at random, and take each nest's remaining blocks
/// off the board (nearest first, buried or not) as if its critters had reached them.
@discardableResult
public func rescueSlots(_ lv: Level, _ s: inout State, _ rng: RNG, _ count: Int) -> Int {
    var picked: [Slot] = []
    var pool = s.sl
    var k = 0
    while k < count && !pool.isEmpty {
        let n = pool.remove(at: rng.int(pool.count))
        picked.append(n)
        var r = n.r
        while r > 0 {
            let i = magicPick(lv, s, n.c)
            if i < 0 { break }
            removeMagic(lv, &s, i)
            r -= 1
        }
        k += 1
    }
    for n in picked { nestDone(&s, n) }
    let ids = Set(picked.map(\.id))
    s.sl.removeAll { ids.contains($0.id) }
    return picked.count
}

// MARK: - Memo key

/// Identifies a position for the solver's dead-end memo (JS stateKey).
struct StateKey: Hashable {
    let lp: [Int]
    let tk: [[UInt8]]
    let sl: [Slot]
    let debt: [Int]
    let locked: Bool
    let b: [UInt8]

    init(_ s: State) {
        lp = s.lp
        tk = s.tk
        // The JS key ignores nest ids: two positions that differ only in ids are the same position.
        sl = s.sl.map { Slot(c: $0.c, r: $0.r, id: 0, k: $0.k, w: $0.w, key: $0.key) }
        debt = s.debt
        locked = s.locked
        b = s.b
    }
}
