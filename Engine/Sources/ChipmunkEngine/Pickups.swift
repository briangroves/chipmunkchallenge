import Foundation

/* ---- Mystery boxes (JS setupPickups, artSpots) ----
   A tool hides in a 3x3 pocket cut into the board. When the critters' open area reaches the pocket, the box goes on
   hold; clearing the board without help opens it on the win card.

   The web game cuts the pocket out of a finished board and takes its nine blocks off their nests (like Acorn Drop).
   That shifts which nests come up short: the critters then leave nine nearby blocks the board's solution expected
   gone, and those can wall off other colors, so boards that clear without a box got stuck with one. Here the pocket
   is cut out of the picture before the board is built (`pocketBase`), so the builder plans its nests around the hole
   and the board is as solvable as any other. Which boards get boxes, the tools inside and where they sit are the web
   game's, pick for pick.

   How many: the warm-up hands out each tool on a schedule so new players meet them all; after that every third board
   has a box (sometimes two), every tenth board is a treasure board with three, and other boards sometimes have one.
   Every Coin Mining board has one, sometimes two, and the daily puzzle has one. About half the time a box sits on a
   feature of the picture (an eye, a window, a button) and takes its place in the drawing. */

/// Pocket size in blocks.
public let POCKET = 3

/// Which kind of board the boxes are for: it decides how many there are.
public enum PickupBoard: Sendable {
    /// Warm-up (Food pack) board, 1-based within the pack.
    case warmup(Int)
    /// Level Play board, 1-based over the whole ramp.
    case level(Int)
    case mining
    case daily
}

/// One mystery box on the board.
public struct Pickup: Equatable, Sendable {
    /// Top-left board cell of the pocket, and its row and column.
    public let at: Int
    public let r: Int
    public let c: Int
    /// The pocket's nine board cells.
    public let cells: [Int]
    /// The tool inside: "owl", "peek", "drop", "wand" or "slot".
    public let tool: String
    /// Identifies this box on this board, so a box opened on an earlier win isn't handed out again.
    public let key: String
    /// Already opened on an earlier win (Coin Mining shows it again with a check).
    public let claimed: Bool
    /// Reached this try.
    public var got: Bool

    /// The critters' open area reaches the pocket.
    public func reached(_ s: State) -> Bool { cells.contains { s.o[$0] != 0 } }
}

/// Warm-up schedule (JS PICK_SCHED): board within the pack -> tools, "?" for a random one.
let PICK_SCHED: [Int: [String]] = [3: ["owl"], 6: ["drop"], 8: ["peek"], 10: ["slot"], 12: ["?"], 15: ["wand"],
                                   18: ["?"], 20: ["?", "?"]]

/// A box's tool from a random number in 0..<1: owl 30%, peek 20%, drop 25%, wand 12.5%, slot 12.5%.
public func randTool(_ u: Double) -> String {
    u < 0.3 ? "owl" : u < 0.5 ? "peek" : u < 0.75 ? "drop" : u < 0.875 ? "wand" : "slot"
}

/// This board's mystery boxes, placed on the start position `s`. `rows` is the picture, `id` the picture's id,
/// `index` the board's place in the web game's level list (it seeds the choice with `seed`), and `claimed` the keys
/// of boxes already opened. Same picks, in the same order, as the web game. The board itself is left as it is.
public func placePickups(_ lv: Level, _ s: State, rows: [String], id: String, seed: Int, index li: Int,
                         board: PickupBoard, claimed: Set<String>) -> [Pickup] {
    var h = UInt32(truncatingIfNeeded: seed &* 2_654_435_761 &+ li &* 97)
    func rnd() -> Double {
        h = UInt32(truncatingIfNeeded: Int(h) &* 1_664_525 &+ 1_013_904_223)
        return Double(h) / 4_294_967_296
    }
    var types: [String] = []
    var para = false
    switch board {
    case .warmup(let k):
        types = (PICK_SCHED[k] ?? []).map { $0 == "?" ? randTool(rnd()) : $0 }
    case .daily:
        types = [randTool(rnd())]
    case .mining:
        para = true
        types = [randTool(rnd())]
        if rnd() < 0.35 { types.append(randTool(rnd())) }
    case .level(let n):
        let k = n % 10 == 0 ? 3 : n % 3 == 0 ? (rnd() < 0.35 ? 2 : 1) : (rnd() < 0.3 ? 1 : 0)
        for _ in 0..<k { types.append(randTool(rnd())) }
    }
    if types.isEmpty { return [] }

    let W = lv.W, H = lv.H, P = POCKET
    var spots = artSpots(rows)
    var out: [Pickup] = []
    /* Pocket test: the 3x3 must be solid blocks; strict 2 also wants its ring solid and not yet edible, strict 1 not
       yet touching the open area, strict 0 just solid. */
    func fits(_ r: Int, _ c: Int, _ strict: Int) -> Bool {
        if r < 1 || c < 1 || r + P > H - 1 || c + P > W - 1 { return false }
        let lo = strict != 0 ? -1 : 0, hi = strict != 0 ? P : P - 1
        for dr in lo...hi {
            for dc in lo...hi {
                let j = (r + dr) * W + c + dc
                if s.b[j] == 0 || s.b[j] == ROCK || (strict == 2 && s.ed[j] != 0) || (strict != 0 && s.o[j] != 0) {
                    return false
                }
            }
        }
        return !out.contains { abs($0.r - r) < P + 3 && abs($0.c - c) < P + 3 }
    }
    for (idx, t) in types.enumerated() {
        let key = "\(id)|\(seed)|\(t)|\(idx)"
        let was = claimed.contains(key)
        if was && !para { continue }
        var at = -1
        if rnd() < 0.5 {   // part of the picture
            while !spots.isEmpty && at < 0 {
                let sp = spots.removeFirst()
                if fits(sp.r, sp.c, 2) || fits(sp.r, sp.c, 1) { at = sp.r * W + sp.c }
            }
        }
        for strict in [2, 1, 0] {
            var tries = 0
            while tries < 400 && at < 0 {
                let r = 3 + Int(rnd() * Double(H - P - 5)), c = 2 + Int(rnd() * Double(W - P - 3))
                if fits(r, c, strict) { at = r * W + c }
                tries += 1
            }
            if at >= 0 { break }
        }
        if at < 0 { continue }
        var cells: [Int] = []
        for dr in 0..<P { for dc in 0..<P { cells.append(at + dr * W + dc) } }
        out.append(Pickup(at: at, r: at / W, c: at % W, cells: cells, tool: t, key: key, claimed: was, got: was))
    }
    return out
}

/// The board's picture with its mystery-box pockets cut out (each 3x3 left empty), and the boxes. Build the board
/// from the returned base: the pockets are part of the picture, so the builder's solution already accounts for them.
/// Rocks and the lock carry over unchanged (a pocket never sits on a rock).
public func pocketBase(_ base: LevelBase, id: String, seed: Int, index: Int, board: PickupBoard,
                       claimed: Set<String>) -> (base: LevelBase, pickups: [Pickup]) {
    let art = Art(base, slots: 5)
    let lv = Level(art: art, slots: 5, lanes: [])
    let s = initState(lv)
    let p = placePickups(lv, s, rows: base.rows, id: id, seed: seed, index: index, board: board, claimed: claimed)
    if p.isEmpty { return (base, []) }
    var grid = base.rows.map { Array($0) }
    for k in p {
        for j in k.cells {
            let r = j / art.W, c = j % art.W
            if r < grid.count && c < grid[r].count { grid[r][c] = "." }
        }
    }
    var out = base
    out.rows = grid.map { String($0) }
    return (out, p)
}

/// Features of a picture a box can stand in for (JS artSpots): small patches of one colour fully ringed by another
/// (a pupil in an eye, a window in a wall, a button, a seed), roughly 3x3, away from the edges. Best first.
func artSpots(_ rows: [String]) -> [(r: Int, c: Int)] {
    let grid = rows.map { Array($0) }
    let H = grid.count, W = grid.first?.count ?? 0
    var seen = [Bool](repeating: false, count: W * H)
    var out: [(r: Int, c: Int, score: Double, n: Int)] = []
    for i in 0..<(W * H) where !seen[i] {
        let ch = grid[i / W][i % W]
        var q = [i], comp: [Int] = []
        seen[i] = true
        while let j = q.popLast() {
            comp.append(j)
            let r = j / W, c = j % W
            for (dr, dc) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let rr = r + dr, cc = c + dc
                if rr < 0 || cc < 0 || rr >= H || cc >= W { continue }
                let k = rr * W + cc
                if !seen[k] && grid[rr][cc] == ch {
                    seen[k] = true
                    q.append(k)
                }
            }
        }
        if comp.count < 3 || comp.count > 20 { continue }
        var r0 = H, r1 = 0, c0 = W, c1 = 0, sr = 0, sc = 0
        for j in comp {
            let r = j / W, c = j % W
            r0 = min(r0, r); r1 = max(r1, r); c0 = min(c0, c); c1 = max(c1, c)
            sr += r; sc += c
        }
        if r1 - r0 > 4 || c1 - c0 > 4 || r0 < 3 || c0 < 3 || r1 > H - 4 || c1 > W - 4 { continue }
        var ring = Set<Character>()
        for j in comp {
            let r = j / W, c = j % W
            for (dr, dc) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where grid[r + dr][c + dc] != ch {
                ring.insert(grid[r + dr][c + dc])
            }
        }
        let n = Double(comp.count)
        let cy = JS.roundInt(Double(sr) / n), cx = JS.roundInt(Double(sc) / n)
        let mid = hypot(Double(cx) - Double(W) / 2, Double(cy) - Double(H) / 2) / (Double(W) / 2)
        let score = (ring.count == 1 ? 3 : ring.count == 2 ? 1.5 : 0) + (ch == "K" || ch == "W" ? 1 : 0)
            - abs(n - 9) / 9 - mid
        out.append((cy - 1, cx - 1, score, out.count))
    }
    // JS sort is stable: equal scores keep their order.
    out.sort { $0.score != $1.score ? $0.score > $1.score : $0.n < $1.n }
    return out.prefix(12).map { ($0.r, $0.c) }
}
