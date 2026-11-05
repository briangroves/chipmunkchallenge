import Foundation

/* ---- New mechanics, introduced slowly through Level Play (board n = 1…170) ----
   Rocks first appear on board 25 (one small clump), then turn up more often and in bigger groups. The locked slot first
   appears on board 45, then on a growing share of boards. Coin Mining has neither. */
public let ROCKS_FROM = 25, LOCK_FROM = 45

public func rockClumps(_ n: Int) -> Int {
    if n < ROCKS_FROM { return 0 }
    if n == ROCKS_FROM { return 1 }
    let r = RNG(seed: n * 7919 + 17)
    let p = min(0.7, 0.2 + Double(n - ROCKS_FROM) / 160)
    return r.next() < p ? 1 + Int(r.next() * min(4, 1 + Double(n - ROCKS_FROM) / 45)) : 0
}

public func lockFor(_ n: Int) -> Bool {
    if n < LOCK_FROM { return false }
    if n == LOCK_FROM { return true }
    return RNG(seed: n * 104_729 + 5).next() < min(0.45, 0.12 + Double(n - LOCK_FROM) / 250)
}

let ROCK_SHAPES: [[(Int, Int)]] = [
    [(0, 0), (0, 1), (1, 0), (1, 1)],
    [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2)],
    [(0, 1), (1, 0), (1, 1), (1, 2), (2, 1)],
    [(0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (1, 3), (2, 1), (2, 2)],
]

/// Rocks go where they read as part of the scene: small rounded clumps placed mostly over background colours (the
/// colours along the board's edge), kept apart from each other and from the edge so they can never wall anything in.
public func rocksFor(_ rowsIn: [String], _ n: Int) -> [Int]? {
    let k = rockClumps(n)
    if k == 0 { return nil }
    let rows = rowsIn.map { Array($0) }
    let H = rows.count, W = rows[0].count, r = RNG(seed: n * 31 + 7)
    func at(_ q: Int, _ c: Int) -> Character? { c < rows[q].count ? rows[q][c] : nil }
    var edge: [Character?: Int] = [:]
    for c in 0..<W {
        edge[at(0, c), default: 0] += 1
        edge[at(H - 1, c), default: 0] += 1
    }
    for q in 0..<H {
        edge[at(q, 0), default: 0] += 1
        edge[at(q, W - 1), default: 0] += 1
    }
    var out: [Int] = []
    var taken: [Int] = []
    for _ in 0..<k {
        let shape = ROCK_SHAPES[min(ROCK_SHAPES.count - 1, Int(r.next() * min(4, 1 + Double(n) / 50)))]
        var best: [Int]?
        var bs = -1.0
        for _ in 0..<80 {
            let r0 = 6 + Int(r.next() * Double(H - 14)), c0 = 3 + Int(r.next() * Double(W - 8))
            let cells = shape.map { (r0 + $0.0) * W + c0 + $0.1 }
            let clash = taken.contains { j in
                cells.contains { i in max(abs(i / W - j / W), abs(i % W - j % W)) < 4 }
            }
            if clash { continue }
            let sc = Double(cells.reduce(0) { $0 + (edge[at($1 / W, $1 % W)] ?? 0) }) + r.next()
            if sc > bs {
                bs = sc
                best = cells
            }
        }
        if let best {
            out += best
            taken += best
        }
    }
    return out.isEmpty ? nil : out
}

/// What the builder needs for Level Play board n (1...170): the picture plus this board's rocks and locked slot.
/// Pass n = 0 for Coin Mining and photo boards (no rocks, no lock).
public func levelBase(name: String, rows: [String], boardNumber n: Int) -> LevelBase {
    var b = LevelBase(name: name, rows: rows)
    if n > 0 {
        b.rocks = rocksFor(rows, n)
        if lockFor(n) { b.lock = true }
        if n >= LOCK_FROM { b.lockOK = true }
    }
    return b
}
