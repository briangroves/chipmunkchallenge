import Foundation

/* ---- Terrain for the native game's later boards (since 2026-11-21) ----
   Three additions on top of the web game's rocks and lock, all seeded from the board number so a board always comes
   out the same:

   - Boulders (from BOULDERS_FROM): now and then one rock clump is a big boulder field instead of a 2x2-3x4 clump.
   - Lakes (from LAKE_FROM): one rounded body of water, usually over the picture's backdrop (blue backdrop most of all).
     Critters can't cross it, so it reshapes the routes and the order the board opens up in.
   - Burrows (from BURROW_FROM): two holes joined underground. Some lakes are a moat round an island, reachable only
     through a burrow; other boards get a shortcut burrow from near the edge into the middle of the picture.

   Every board is checked so each block can still be reached from the edge (through burrows where there are any).
   A layout that would wall blocks in is dropped, so terrain never makes a board impossible.

   The web game has none of this, so `levelBase(..., terrain: false)` (the parity tests) leaves it out. */

public let BOULDERS_FROM = 60, LAKE_FROM = 75, BURROW_FROM = 100

/// Fewest blocks a lake keeps between itself and the board's edge.
let LAKE_MARGIN = 2

/// What a board's terrain adds to the picture.
public struct Terrain: Equatable, Sendable {
    public var rocks: [Int] = []
    public var water: [Int] = []
    /// Pairs of board cells, [a0, b0, a1, b1, ...].
    public var burrows: [Int] = []
}

/// A lake shows up on the first lake board, then on a growing share of boards.
public func lakeFor(_ n: Int) -> Bool {
    if n < LAKE_FROM { return false }
    if n == LAKE_FROM { return true }
    return RNG(seed: n * 15_485_863 + 11).next() < min(0.45, 0.2 + Double(n - LAKE_FROM) / 300)
}

/// A lake that is a moat round an island (needs burrows).
func moatFor(_ n: Int) -> Bool {
    if n < BURROW_FROM { return false }
    if n == BURROW_FROM { return true }
    return RNG(seed: n * 982_451_653 + 3).next() < min(0.5, 0.25 + Double(n - BURROW_FROM) / 400)
}

/// A shortcut burrow on a board with no moat.
func shortcutFor(_ n: Int) -> Bool {
    n > BURROW_FROM && RNG(seed: n * 32_452_843 + 9).next() < min(0.3, 0.12 + Double(n - BURROW_FROM) / 500)
}

/// One rock clump becomes a boulder field.
func boulderFor(_ n: Int) -> Bool {
    if n < BOULDERS_FROM { return false }
    if n == BOULDERS_FROM { return true }
    return RNG(seed: n * 49_979_687 + 1).next() < min(0.4, 0.15 + Double(n - BOULDERS_FROM) / 300)
}

// MARK: - Shapes

/// A rounded blob of about `area` cells centred on (r0, c0): an ellipse with a wobbly edge, one piece, no holes.
func blob(W: Int, H: Int, r0: Int, c0: Int, area: Int, aspect: Double, _ r: RNG) -> Set<Int> {
    let R = (Double(area) / Double.pi).squareRoot()
    let ry = R / aspect.squareRoot(), rx = R * aspect.squareRoot()
    let p1 = r.next() * 6.283, p2 = r.next() * 6.283, a1 = 0.08 + r.next() * 0.1, a2 = 0.05 + r.next() * 0.08
    var cells = Set<Int>()
    let span = Int((max(rx, ry) * 1.4).rounded(.up))
    for dr in -span...span {
        for dc in -span...span {
            let rr = r0 + dr, cc = c0 + dc
            if rr < 0 || cc < 0 || rr >= H || cc >= W { continue }
            let y = Double(dr) / ry, x = Double(dc) / rx, th = atan2(y, x)
            let edge = 1 + a1 * sin(2 * th + p1) + a2 * sin(3 * th + p2)
            if (x * x + y * y).squareRoot() <= edge { cells.insert(rr * W + cc) }
        }
    }
    return solidOnePiece(cells, W: W, H: H, from: r0 * W + c0)
}

/// The piece of `cells` holding `from`, with any holes inside it filled.
func solidOnePiece(_ cells: Set<Int>, W: Int, H: Int, from: Int) -> Set<Int> {
    guard cells.contains(from) else { return cells }
    var piece: Set<Int> = [from], q = [from]
    while let i = q.popLast() {
        for j in neighbors(i, W: W, H: H) where cells.contains(j) && !piece.contains(j) {
            piece.insert(j)
            q.append(j)
        }
    }
    // Fill holes: cells not in the piece that can't reach the edge without crossing it.
    var outside = Set<Int>()
    q = []
    for i in 0..<(W * H) where !piece.contains(i) {
        let r = i / W, c = i % W
        if r == 0 || c == 0 || r == H - 1 || c == W - 1 {
            outside.insert(i)
            q.append(i)
        }
    }
    while let i = q.popLast() {
        for j in neighbors(i, W: W, H: H) where !piece.contains(j) && !outside.contains(j) {
            outside.insert(j)
            q.append(j)
        }
    }
    for i in 0..<(W * H) where !piece.contains(i) && !outside.contains(i) { piece.insert(i) }
    return piece
}

@inline(__always) func neighbors(_ i: Int, W: Int, H: Int) -> [Int] {
    let r = i / W, c = i % W
    var out: [Int] = []
    out.reserveCapacity(4)
    if r > 0 { out.append(i - W) }
    if r < H - 1 { out.append(i + W) }
    if c > 0 { out.append(i - 1) }
    if c < W - 1 { out.append(i + 1) }
    return out
}

/// Chebyshev distance between two cells.
@inline(__always) func gap(_ a: Int, _ b: Int, W: Int) -> Int { max(abs(a / W - b / W), abs(a % W - b % W)) }

// MARK: - Reachability

/// Cells (not rock or water) a critter can't get to from the board's edge, even digging through every block and
/// using every burrow. A burrow end is open ground, so `burrows` pass through.
func walledIn(W: Int, H: Int, solid: Set<Int>, burrows: [Int]) -> [Int] {
    var link: [Int: Int] = [:]
    for k in stride(from: 0, to: burrows.count - 1, by: 2) {
        link[burrows[k]] = burrows[k + 1]
        link[burrows[k + 1]] = burrows[k]
    }
    var seen = [Bool](repeating: false, count: W * H), q: [Int] = []
    for i in 0..<(W * H) where !solid.contains(i) {
        let r = i / W, c = i % W
        if r == 0 || c == 0 || r == H - 1 || c == W - 1 {
            seen[i] = true
            q.append(i)
        }
    }
    while let i = q.popLast() {
        var next = neighbors(i, W: W, H: H)
        if let p = link[i] { next.append(p) }
        for j in next where !seen[j] && !solid.contains(j) {
            seen[j] = true
            q.append(j)
        }
    }
    return (0..<(W * H)).filter { !seen[$0] && !solid.contains($0) }
}

// MARK: - Placement

/// How much each picture colour belongs to the backdrop: how often it runs along the board's edge.
func edgeWeight(_ rows: [[Character]]) -> [Character: Double] {
    let H = rows.count, W = rows.first?.count ?? 0
    var edge: [Character: Double] = [:]
    func at(_ r: Int, _ c: Int) -> Character { c < rows[r].count ? rows[r][c] : "." }
    for c in 0..<W {
        edge[at(0, c), default: 0] += 1
        edge[at(H - 1, c), default: 0] += 1
    }
    for r in 0..<H {
        edge[at(r, 0), default: 0] += 1
        edge[at(r, W - 1), default: 0] += 1
    }
    let top = max(1, edge.values.max() ?? 1)
    return edge.mapValues { $0 / top }
}

/// Picture letters that read as water when a lake covers them.
let WATERY: Set<Character> = ["B", "C", "U"]

/// Score a set of cells as terrain: high over the backdrop (and, for a lake, over blue), low over the subject.
func backdropScore(_ cells: Set<Int>, _ rows: [[Character]], _ edge: [Character: Double], W: Int, lake: Bool) -> Double {
    var sc = 0.0
    for i in cells {
        let r = i / W, c = i % W
        let ch = c < rows[r].count ? paletteLetter(rows[r][c]) : "."
        sc += (edge[ch] ?? 0) - 0.35
        if lake && WATERY.contains(ch) { sc += 0.6 }
    }
    return sc / Double(max(1, cells.count))
}

/// The picture's backdrop: cells of the colours that run along the board's edge, joined to the edge through such
/// cells. Everything else is the subject (or part of it).
func backdropMask(_ rows: [[Character]], _ edge: [Character: Double]) -> [Bool] {
    let H = rows.count, W = rows.map(\.count).max() ?? 0
    func ch(_ i: Int) -> Character { let r = i / W, c = i % W; return c < rows[r].count ? paletteLetter(rows[r][c]) : "." }
    func backish(_ i: Int) -> Bool { let k = ch(i); return k == "." || (edge[k] ?? 0) >= 0.1 }
    var back = [Bool](repeating: false, count: W * H), q: [Int] = []
    for i in 0..<(W * H) where backish(i) {
        let r = i / W, c = i % W
        if r == 0 || c == 0 || r == H - 1 || c == W - 1 {
            back[i] = true
            q.append(i)
        }
    }
    while let i = q.popLast() {
        for j in neighbors(i, W: W, H: H) where !back[j] && backish(j) {
            back[j] = true
            q.append(j)
        }
    }
    return back
}

/// Least share of a lake's water that must lie on the backdrop.
let LAKE_ON_BACKDROP = 0.95

/// The best place for a lake of about `area` cells (a moat when `moat`): off the board's edge, clear of rocks, with
/// its water on the backdrop; lower in the scene and over blue backdrop is better. Nil when it fits nowhere.
func placeLake(rows: [[Character]], W: Int, H: Int, area: Int, moat: Bool, back: [Bool], edge: [Character: Double],
               rocks: Set<Int>, _ r: RNG) -> (water: Set<Int>, island: Set<Int>)? {
    var best: (water: Set<Int>, island: Set<Int>)?, bs = -Double.infinity
    for _ in 0..<160 {
        let r0 = 3 + Int(r.next() * Double(H - 6)), c0 = 3 + Int(r.next() * Double(W - 6))
        // Only start from the backdrop.
        if !back[r0 * W + c0] && !moat { continue }
        let aspect = moat ? 0.8 + r.next() * 0.5 : 0.9 + r.next() * 2.2
        var w = blob(W: W, H: H, r0: r0, c0: c0, area: area, aspect: aspect, r)
        var island = Set<Int>()
        if moat {
            // Keep the middle as an island: cells at least 3 in from the lake's edge.
            island = w.filter { i in
                let rr = i / W, cc = i % W
                for dr in -2...2 { for dc in -2...2 where !w.contains((rr + dr) * W + cc + dc) { return false } }
                return true
            }
            guard island.count >= 4 else { continue }
            w.subtract(island)
        }
        // A moat stays off the edge (or it wouldn't ring its island); a pond may run to it, like a lake in the
        // foreground, but not along it.
        let m = moat ? LAKE_MARGIN : 0
        if w.contains(where: { let q = $0 / W, c = $0 % W; return q < m || c < m || q > H - 1 - m || c > W - 1 - m }) {
            continue
        }
        if !moat {
            // Along the bottom it reads as water in the foreground; up the sides or across the top it doesn't.
            var side = 0, bottom = 0
            for i in w {
                if i / W == H - 1 { bottom += 1 } else if i / W == 0 || i % W == 0 || i % W == W - 1 { side += 1 }
            }
            if side > 5 || bottom > 20 { continue }
        }
        if w.contains(where: { i in rocks.contains { gap($0, i, W: W) < 2 } }) { continue }
        let onBack = Double(w.filter { back[$0] }.count) / Double(w.count)
        if onBack < LAKE_ON_BACKDROP { continue }
        // Lakes sit low in the scene; an island that holds a bit of the picture is better than an empty one.
        let low = Double(w.reduce(0) { $0 + $1 / W }) / Double(w.count) / Double(H - 1)
        // Keep a strip of backdrop between the water and the subject's outline.
        let touch = w.filter { i in !back[i] || neighbors(i, W: W, H: H).contains { !back[$0] } }.count
        var sc = backdropScore(w, rows, edge, W: W, lake: true) + 2 * onBack + 1.2 * low
            - 2.5 * Double(touch) / Double(w.count)
        if moat { sc += 0.3 * Double(island.filter { !back[$0] }.count) / Double(island.count) }
        sc += r.next() * 0.15
        if sc > bs {
            bs = sc
            best = (w, island)
        }
    }
    return best
}

/// The board's terrain. `rocks` are the web game's clumps for this board (kept unless a boulder field or lake needs
/// their room).
public func terrainFor(_ rowsIn: [String], _ n: Int, rocks: [Int]?) -> Terrain {
    let rows = rowsIn.map { Array($0) }
    let H = rows.count, W = rows.map(\.count).max() ?? 0
    var t = Terrain(rocks: rocks ?? [])
    guard H >= 20, W >= 20 else { return t }
    let edge = edgeWeight(rows)
    let r = RNG(seed: n * 6_700_417 + 29)

    // Boulder field: one large blob of rock (12-26 cells) instead of the smallest clump.
    if boulderFor(n) {
        let area = 12 + Int(r.next() * min(14, 4 + Double(n - BOULDERS_FROM) / 12))
        var best: Set<Int>?, bs = -Double.infinity
        for _ in 0..<60 {
            let r0 = 6 + Int(r.next() * Double(H - 14)), c0 = 4 + Int(r.next() * Double(W - 8))
            let b = blob(W: W, H: H, r0: r0, c0: c0, area: area, aspect: 0.7 + r.next() * 0.9, r)
            if b.contains(where: { let q = $0 / W, c = $0 % W; return q < 2 || c < 2 || q > H - 3 || c > W - 3 }) { continue }
            let sc = backdropScore(b, rows, edge, W: W, lake: false) + r.next() * 0.2
            if sc > bs {
                bs = sc
                best = b
            }
        }
        if let best {
            // It replaces any clump it would crowd.
            t.rocks = t.rocks.filter { i in !best.contains { gap($0, i, W: W) < 4 } }
            t.rocks += best.sorted()
        }
    }

    // Lake: a pond, or (from BURROW_FROM) sometimes a moat round an island. Its water goes on the backdrop, never
    // across the subject: a moat that can't find room becomes a pond, and a pond that can't find room is left out.
    let moat = moatFor(n)
    if lakeFor(n) || moat {
        let back = backdropMask(rows, edge)
        let grow = min(1, Double(n - LAKE_FROM) / 150)
        let rocks = Set(t.rocks)
        var tries: [(moat: Bool, area: Int)] = []
        if moat { tries += [140, 110, 85, 65].map { (true, $0 + Int(r.next() * 15)) } }
        let pond = 36 + Int(r.next() * (40 + 70 * grow))
        tries += [(false, pond), (false, max(30, pond * 2 / 3))]
        for (isMoat, area) in tries {
            guard let best = placeLake(rows: rows, W: W, H: H, area: area, moat: isMoat, back: back, edge: edge,
                                       rocks: rocks, r) else { continue }
            t.water = best.water.sorted()
            if isMoat, let b = moatBurrow(W: W, H: H, water: best.water, island: best.island, r) { t.burrows += b }
            break
        }
    }

    // Shortcut burrow: from just inside the edge to deep in the picture.
    if t.burrows.isEmpty && shortcutFor(n) {
        let solid = Set(t.rocks).union(t.water)
        var best: [Int]?, bs = -1.0
        for _ in 0..<40 {
            let side = Int(r.next() * 3)   // left, right, or top
            let k = 6 + Int(r.next() * Double((side == 2 ? W : H) - 12))
            let a = side == 0 ? k * W + 1 : side == 1 ? k * W + W - 2 : 1 * W + k
            let b = (10 + Int(r.next() * Double(H - 20))) * W + 10 + Int(r.next() * Double(W - 20))
            if solid.contains(a) || solid.contains(b) { continue }
            if solid.contains(where: { gap($0, a, W: W) < 2 || gap($0, b, W: W) < 2 }) { continue }
            let d = Double(gap(a, b, W: W)) + r.next()
            if d > bs {
                bs = d
                best = [a, b]
            }
        }
        if let best { t.burrows += best }
    }

    // Nothing may be walled in. Drop what doesn't fit, worst first: the lake's burrow can't help, so the lake goes;
    // then the boulder field (back to the web game's clumps).
    let solid = Set(t.rocks).union(t.water)
    if !walledIn(W: W, H: H, solid: solid, burrows: t.burrows).isEmpty {
        t.water = []
        t.burrows = t.burrows.count >= 2 && !moatFor(n) ? t.burrows : []
        if !walledIn(W: W, H: H, solid: Set(t.rocks), burrows: t.burrows).isEmpty {
            t.rocks = rocks ?? []
        }
    }
    return t
}

/// The burrow that takes critters from the lakeshore under a moat to its island: the island end just inside its
/// shore, the outer end just outside the moat, as near the board's bottom (where critters come from) as it can be.
func moatBurrow(W: Int, H: Int, water: Set<Int>, island: Set<Int>, _ r: RNG) -> [Int]? {
    func touches(_ i: Int) -> Bool { neighbors(i, W: W, H: H).contains { water.contains($0) } }
    let inner = island.filter(touches).sorted()
    let outer = (0..<(W * H)).filter { !water.contains($0) && !island.contains($0) && touches($0) }
    guard !inner.isEmpty, !outer.isEmpty else { return nil }
    // Pick the outer end low and a little to one side, then the island end nearest it.
    var bo = -1, bs = -Double.infinity
    for o in outer {
        let sc = Double(o / W) + r.next() * 4
        if sc > bs {
            bs = sc
            bo = o
        }
    }
    let bi = inner.min { gap($0, bo, W: W) < gap($1, bo, W: W) }!
    return [bo, bi]
}
