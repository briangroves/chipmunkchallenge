import Foundation

/* ---- Terrain for the native game's later boards (since 2026-11-21) ----
   Three additions on top of the web game's rocks and lock, all decided from the picture and the board number, so a
   board always comes out the same:

   - Boulders (from BOULDERS_FROM): now and then one rock clump is a big boulder field instead of a 2x2-3x4 clump.
   - Lakes (from LAKE_FROM): only where the picture itself draws water, a lake, river or sea (2026-11-24: never made
     up, and never the sky). Which pictures draw water is decided by eye (Resources/water-boards.json, or a feed
     board's own `water` flag); `drawnWater` then finds the water's cells. That water becomes one body of water
     critters can't cross. A piece of the picture the water walls in (an island) gets a burrow to it.
   - Burrows (from BURROW_FROM): two holes joined underground, with or without water: from near the edge into the
     middle of the picture, or between two places deep inside it, so opening one opens the other.

   Every board is checked so each block can still be reached from the edge (through burrows where there are any).
   A layout that would wall blocks in is dropped, so terrain never makes a board impossible.

   The web game has none of this, so `levelBase(..., terrain: false)` (the parity tests) leaves it out. */

public let BOULDERS_FROM = 60, LAKE_FROM = 75, BURROW_FROM = 100

/// What a board's terrain adds to the picture.
public struct Terrain: Equatable, Sendable {
    public var rocks: [Int] = []
    public var water: [Int] = []
    /// Pairs of board cells, [a0, b0, a1, b1, ...].
    public var burrows: [Int] = []
}

/// How many standalone burrows board n gets: none before BURROW_FROM, one on the first burrow board, then one on a
/// growing share of boards, and from board 150 sometimes two.
func burrowCount(_ n: Int) -> Int {
    if n < BURROW_FROM { return 0 }
    if n == BURROW_FROM { return 1 }
    let r = RNG(seed: n * 32_452_843 + 9)
    guard r.next() < min(0.6, 0.35 + Double(n - BURROW_FROM) / 400) else { return 0 }
    return n >= 150 && r.next() < 0.35 ? 2 : 1
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

/// Connected pieces (4-way) of the cells `inside` accepts.
func pieces(W: Int, H: Int, _ inside: (Int) -> Bool) -> [[Int]] {
    var seen = [Bool](repeating: false, count: W * H), out: [[Int]] = []
    for i in 0..<(W * H) where !seen[i] && inside(i) {
        var comp = [i], q = [i]
        seen[i] = true
        while let j = q.popLast() {
            for m in neighbors(j, W: W, H: H) where !seen[m] && inside(m) {
                seen[m] = true
                comp.append(m)
                q.append(m)
            }
        }
        out.append(comp)
    }
    return out
}

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

// MARK: - Backdrop

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

/// Score a set of cells as rock: high over the backdrop, low over the subject.
func backdropScore(_ cells: Set<Int>, _ rows: [[Character]], _ edge: [Character: Double], W: Int) -> Double {
    var sc = 0.0
    for i in cells {
        let r = i / W, c = i % W
        let ch = c < rows[r].count ? paletteLetter(rows[r][c]) : "."
        sc += (edge[ch] ?? 0) - 0.35
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

// MARK: - Water drawn in the picture

/// Picture letters that can be drawn water.
let WATERY: Set<Character> = ["B", "C", "U"]

/// Least cells for drawn water to count as a lake or river.
let WATER_MIN = 20
/// Most of the board drawn water may take; a picture that is mostly sea plays as it is.
let WATER_MAX_SHARE = 0.4
/// Enclosed bits inside the water up to this size (ripples, glints) become water too.
let WATER_HOLE = 6
/// A blue region whose cells sit higher than this share of the board, on average, is sky.
let WATER_LOW = 0.45
/// Water lies below the horizon: none of it reaches higher than this share of the board.
let WATER_TOP = 0.35

/// The lakes and rivers the picture draws: blue regions in the lower part of the scene that lie on the backdrop.
/// Sky is left alone: a blue region that spans a quarter of the top row or more, or sits mostly in the upper part
/// of the board, is sky.
public func drawnWater(_ rowsIn: [String]) -> Set<Int> {
    let rows = rowsIn.map { Array($0) }
    let H = rows.count, W = rows.map(\.count).max() ?? 0
    guard H >= 10, W >= 10 else { return [] }
    func ch(_ i: Int) -> Character { let r = i / W, c = i % W; return c < rows[r].count ? paletteLetter(rows[r][c]) : "." }
    func mid(_ comp: [Int]) -> Double { Double(comp.reduce(0) { $0 + $1 / W }) / Double(comp.count) }
    let back = backdropMask(rows, edgeWeight(rows))

    // 1. Sky, judged one shade at a time (sky and sea in two blues that meet at the horizon stay apart): a region
    //    across the top or high in the scene. Sky showing through lower down, between parts of the subject, is the
    //    same shade, so every region of a sky shade is sky too, except one that reaches the bottom edge (water in
    //    the foreground, drawn in the sky's blue).
    var sky = [Bool](repeating: false, count: W * H)
    var skyShade = Set<Character>()
    var regions: [(k: Character, comp: [Int])] = []
    for k in WATERY {
        for comp in pieces(W: W, H: H, { ch($0) == k }) {
            regions.append((k, comp))
            let top = comp.filter { $0 / W == 0 }.count
            if Double(top) >= 0.25 * Double(W) || mid(comp) < WATER_LOW * Double(H) {
                for j in comp { sky[j] = true }
                if comp.count >= 40 { skyShade.insert(k) }
            }
        }
    }
    for (k, comp) in regions where skyShade.contains(k) && !comp.contains(where: { $0 / W == H - 1 }) {
        for j in comp { sky[j] = true }
    }

    // 2. The rest of the blue, joined across shades (a lake drawn in two blues is one lake).
    var water = Set<Int>()
    for comp in pieces(W: W, H: H, { WATERY.contains(ch($0)) && !sky[$0] }) {
        guard comp.count >= WATER_MIN, mid(comp) >= WATER_LOW * Double(H),
              Double(comp.map { $0 / W }.min()!) >= WATER_TOP * Double(H) else { continue }
        // Part of the scene, not of the subject: a fair part of what borders it is backdrop or the board's edge (a
        // wing or a shirt is ringed by the subject's outline).
        let set = Set(comp)
        var border = 0, scene = 0
        for j in comp {
            let r = j / W, c = j % W
            if r == 0 || c == 0 || r == H - 1 || c == W - 1 {
                border += 1
                scene += 1
            }
            for m in neighbors(j, W: W, H: H) where !set.contains(m) {
                border += 1
                if back[m] { scene += 1 }
            }
        }
        // (Loose: it only runs on pictures already known to draw water.)
        guard Double(scene) >= 0.25 * Double(max(1, border)) else { continue }
        water.formUnion(comp)
    }
    guard !water.isEmpty else { return [] }

    // 3. Small bits the water encloses (highlights drawn on it) are water too; bigger ones (a duck, an island) stay.
    let open = Set(walledIn(W: W, H: H, solid: water, burrows: []))
    for comp in pieces(W: W, H: H, { open.contains($0) }) where comp.count <= WATER_HOLE { water.formUnion(comp) }
    if Double(water.count) > WATER_MAX_SHARE * Double(W * H) { return [] }
    return water
}

/// Burrows to every piece of the picture the water walls in: one end just outside the water, as low on the board as
/// it can be (critters come from below), the other just inside the island's shore, nearest it.
func islandBurrows(W: Int, H: Int, solid: Set<Int>, water: Set<Int>) -> [Int] {
    var out: [Int] = []
    func shore(_ i: Int) -> Bool { neighbors(i, W: W, H: H).contains { water.contains($0) } }
    for _ in 0..<6 {
        let shut = Set(walledIn(W: W, H: H, solid: solid, burrows: out))
        guard let start = shut.min() else { break }
        var island: Set<Int> = [start], q = [start]
        while let i = q.popLast() {
            for j in neighbors(i, W: W, H: H) where shut.contains(j) && !island.contains(j) {
                island.insert(j)
                q.append(j)
            }
        }
        let used = Set(out)
        let outer = (0..<(W * H)).filter { !solid.contains($0) && !shut.contains($0) && !used.contains($0) && shore($0) }
        let inner = island.filter { shore($0) && !used.contains($0) }
        guard let bo = outer.max(by: { ($0 / W, -abs($0 % W - W / 2)) < ($1 / W, -abs($1 % W - W / 2)) }),
              let bi = inner.min(by: { gap($0, bo, W: W) < gap($1, bo, W: W) }) else { break }
        out += [bo, bi]
    }
    return out
}

// MARK: - Burrows on their own

/// A cell in the middle of a big patch of one colour, so a hole never lands on a small detail like an eye.
func plainSpot(_ i: Int, _ rows: [[Character]], W: Int, H: Int) -> Bool {
    let r = i / W, c = i % W
    guard r >= 2, c >= 2, r < H - 2, c < W - 2, c < rows[r].count else { return false }
    let k = rows[r][c]
    var same = 0
    for dr in -2...2 {
        for dc in -2...2 where c + dc < rows[r + dr].count && rows[r + dr][c + dc] == k { same += 1 }
    }
    return same >= 23
}

/// One standalone burrow clear of `avoid` (rocks, water) and of the ends already placed: from just inside the edge
/// into the depths of the picture, or between two places deep inside it.
func standaloneBurrow(_ rows: [[Character]], W: Int, H: Int, avoid: Set<Int>, ends: [Int], _ r: RNG) -> [Int]? {
    func depth(_ i: Int) -> Int { min(i / W, i % W, H - 1 - i / W, W - 1 - i % W) }
    func clear(_ i: Int) -> Bool {
        !avoid.contains { gap($0, i, W: W) < 2 } && !ends.contains { gap($0, i, W: W) < 6 }
    }
    let deep = (0..<(W * H)).filter { depth($0) >= 8 && plainSpot($0, rows, W: W, H: H) && clear($0) }
    guard !deep.isEmpty else { return nil }
    let fromEdge = r.next() < 0.5
    var best: [Int]?, bs = -1.0
    for _ in 0..<80 {
        let b = deep[min(deep.count - 1, Int(r.next() * Double(deep.count)))]
        let a: Int
        if fromEdge {
            // Just inside the left, right or top edge (the bottom is where critters start anyway).
            let side = Int(r.next() * 3), k = 4 + Int(r.next() * Double((side == 2 ? W : H) - 8))
            a = side == 0 ? k * W + 1 : side == 1 ? k * W + W - 2 : W + k
            guard clear(a) else { continue }
        } else {
            a = deep[min(deep.count - 1, Int(r.next() * Double(deep.count)))]
        }
        let d = Double(gap(a, b, W: W))
        if d < 12 { continue }
        let sc = d + r.next() * 6
        if sc > bs {
            bs = sc
            best = [a, b]
        }
    }
    return best
}

// MARK: - The board's terrain

/// The board's terrain. `rocks` are the web game's clumps for this board (kept unless a boulder field or water
/// needs their room). `drawsWater`: the picture is known to draw a lake, river or sea (LevelCatalog.drawsWater); only
/// then does its blue become water.
public func terrainFor(_ rowsIn: [String], _ n: Int, rocks: [Int]?, drawsWater: Bool = false) -> Terrain {
    let rows = rowsIn.map { Array($0) }
    let H = rows.count, W = rows.map(\.count).max() ?? 0
    var t = Terrain(rocks: rocks ?? [])
    guard H >= 20, W >= 20 else { return t }
    let edge = edgeWeight(rows)
    let r = RNG(seed: n * 6_700_417 + 29)
    let water = n >= LAKE_FROM && drawsWater ? drawnWater(rowsIn) : []

    // Boulder field: one large blob of rock (12-26 cells) instead of the smallest clump, on the backdrop.
    if boulderFor(n) {
        let area = 12 + Int(r.next() * min(14, 4 + Double(n - BOULDERS_FROM) / 12))
        var best: Set<Int>?, bs = -Double.infinity
        for _ in 0..<60 {
            let r0 = 6 + Int(r.next() * Double(H - 14)), c0 = 4 + Int(r.next() * Double(W - 8))
            let b = blob(W: W, H: H, r0: r0, c0: c0, area: area, aspect: 0.7 + r.next() * 0.9, r)
            if b.contains(where: { let q = $0 / W, c = $0 % W; return q < 2 || c < 2 || q > H - 3 || c > W - 3 }) { continue }
            if b.contains(where: { i in water.contains { gap($0, i, W: W) < 2 } }) { continue }
            let sc = backdropScore(b, rows, edge, W: W) + r.next() * 0.2
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

    // Lakes and rivers: only the water the picture draws. Rocks never sit in or right beside it.
    if !water.isEmpty {
        t.water = water.sorted()
        t.rocks = t.rocks.filter { i in !water.contains { gap($0, i, W: W) < 2 } }
        t.burrows += islandBurrows(W: W, H: H, solid: Set(t.rocks).union(water), water: water)
    }

    // Burrows on their own.
    for _ in 0..<burrowCount(n) {
        if let b = standaloneBurrow(rows, W: W, H: H, avoid: Set(t.rocks).union(t.water), ends: t.burrows, r) {
            t.burrows += b
        }
    }

    // Nothing may be walled in (blank cells don't matter). Drop what doesn't fit: first the water (and the burrows
    // that went to its islands), then the boulder field (back to the web game's clumps).
    func shutBlocks() -> Bool {
        let ends = Set(t.burrows)
        return walledIn(W: W, H: H, solid: Set(t.rocks).union(t.water), burrows: t.burrows).contains { i in
            let q = i / W, c = i % W
            return c < rows[q].count && rows[q][c] != "." && !ends.contains(i)
        }
    }
    if shutBlocks() {
        var kept: [Int] = []
        for k in stride(from: 0, to: t.burrows.count - 1, by: 2) {
            let pair = [t.burrows[k], t.burrows[k + 1]]
            if !pair.contains(where: { i in neighbors(i, W: W, H: H).contains { water.contains($0) } }) { kept += pair }
        }
        t.water = []
        t.burrows = kept
        if shutBlocks() { t.rocks = rocks ?? [] }
    }
    return t
}
