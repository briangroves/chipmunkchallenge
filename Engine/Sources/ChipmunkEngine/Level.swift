import Foundation

/// A permanent obstacle cell. Solid (critters walk round it, it gives cover), never edible, never carried, and not
/// counted in the board's total, so a board is won when every other block is gone.
public let ROCK: UInt8 = 255

/// The 25 colors, keyed by the letter a picture row uses: 18 standard ones and 7 in-between shades.
public let PALETTE: [Character: UInt32] = [
    "R": 0xE53935, "O": 0xFB8C00, "Y": 0xFDD835, "G": 0x43A047, "B": 0x1E88E5, "V": 0x8E24AA,
    "P": 0xF48FB1, "N": 0x795548, "W": 0xF5F5F5, "K": 0x263238, "T": 0xD2B48C, "A": 0x9E9E9E,
    "L": 0x9CCC65, "D": 0x1B5E20, "M": 0x8E1B1B, "C": 0x81D4FA, "U": 0x283593, "I": 0xB39DDB,
    // In-between shades, for shadows, highlights and soft skies.
    "Q": 0xE65100, "J": 0xFFB74D, "H": 0xB3E5FC, "E": 0x4E342E, "S": 0xD81B60, "Z": 0xFFF59D, "X": 0xD7CCC8,
]

public let COLOR_NAME: [Character: String] = [
    "R": "red", "O": "orange", "Y": "yellow", "G": "green", "B": "blue", "V": "purple", "P": "pink",
    "N": "brown", "W": "white", "K": "black", "T": "tan", "A": "grey", "L": "light green", "D": "dark green",
    "M": "maroon", "C": "sky blue", "U": "navy", "I": "lavender",
    "Q": "deep orange", "J": "peach", "H": "pale blue", "E": "dark brown", "S": "raspberry", "Z": "pale yellow",
    "X": "stone",
]

/// The picture a board is built from, plus what this board adds to it (rocks, a locked slot).
public struct LevelBase: Codable, Equatable, Sendable {
    public var name: String
    public var rows: [String]
    public var rocks: [Int]?
    public var lock: Bool
    /// The builder may add a lock to a board that comes out far too easy.
    public var lockOK: Bool

    public init(name: String, rows: [String], rocks: [Int]? = nil, lock: Bool = false, lockOK: Bool = false) {
        self.name = name
        self.rows = rows
        self.rocks = rocks
        self.lock = lock
        self.lockOK = lockOK
    }
}

/// One nest waiting in a lane: `n` critters of color `c`. A key nest opens the locked slot when it finishes.
public struct NestSpec: Codable, Equatable, Hashable, Sendable {
    public var c: Int
    public var n: Int
    public var key: Bool

    public init(c: Int, n: Int, key: Bool = false) {
        self.c = c
        self.n = n
        self.key = key
    }

    enum CodingKeys: String, CodingKey { case c, n, key }

    public init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        c = try v.decode(Int.self, forKey: .c)
        n = try v.decode(Int.self, forKey: .n)
        key = try v.decodeIfPresent(Bool.self, forKey: .key) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var v = encoder.container(keyedBy: CodingKeys.self)
        try v.encode(c, forKey: .c)
        try v.encode(n, forKey: .n)
        if key { try v.encode(true, forKey: .key) }
    }
}

/// The parsed picture (JS `parseArt`). Immutable and shared between every level object built from it.
public struct Art: Sendable {
    public let W: Int
    public let H: Int
    /// Color index per cell: 0 empty, 1... a color (see `chars`), ROCK for a rock.
    public let cells: [UInt8]
    /// Palette letter of color index k+1.
    public let chars: [Character]
    /// Blocks of each color index (index 0 unused).
    public let counts: [Int]
    public let total: Int
    /// Pickup order: the "measured" distance from the bottom center of the board.
    public let key: [Int]
    public let lock: Bool
    public let lockAt: Int

    public init(rows: [String], rocks: [Int]?, lock: Bool, slots: Int) {
        let grid = rows.map { Array($0) }
        let H = grid.count
        let W = grid.map(\.count).max() ?? 0
        var chars: [Character] = []
        var cells = [UInt8](repeating: 0, count: W * H)
        for r in 0..<H {
            for c in 0..<W {
                let ch: Character = c < grid[r].count ? grid[r][c] : "."
                if ch == "." { continue }
                var k = chars.firstIndex(of: ch) ?? -1
                if k < 0 {
                    chars.append(ch)
                    k = chars.count - 1
                }
                cells[r * W + c] = UInt8(k + 1)
            }
        }
        if let rocks { for i in rocks { cells[i] = ROCK } }
        var counts = [Int](repeating: 0, count: chars.count + 1)
        var total = 0
        for v in cells where v != 0 && v != ROCK {
            counts[Int(v)] += 1
            total += 1
        }
        /* Horizontal + 3 × vertical distance from the bottom center, so ants clear a wide stretch of a row before
           starting on the row above. Ties go to the lower row, then the left. Kept doubled so it stays an integer. */
        var key = [Int](repeating: 0, count: W * H)
        for r in 0..<H {
            for c in 0..<W {
                key[r * W + c] = (abs(2 * c + 1 - W) + 3 * (2 * (H - 1 - r) + 1)) * 4096 + (H - 1 - r) * 64 + c
            }
        }
        self.W = W
        self.H = H
        self.cells = cells
        self.chars = chars
        self.counts = counts
        self.total = total
        self.key = key
        self.lock = lock
        self.lockAt = slots - 1
    }

    public init(_ def: LevelBase, slots: Int) {
        self.init(rows: def.rows, rocks: def.rocks, lock: def.lock, slots: slots)
    }
}

/// Layout of the ants' world, in cells: a one-cell walkway on the top, left and right of the picture, and below it an
/// 8-row apron of open ground. The drain sits in the middle of the apron.
public enum MG {
    public static let t = 1, l = 1, r = 1, b = 8
}

/// A playable board: the picture, its slots and lanes, the navigation grid, and the builder's notes.
/// A class because the simulation keeps scratch buffers here and "Extra Slot" changes the slot count mid-game.
public final class Level {
    public let art: Art
    public var slots: Int
    public var lanes: [[NestSpec]]

    // Navigation (set by navSetup).
    public private(set) var hasNav = false
    public private(set) var NW = 0
    public private(set) var NH = 0
    public private(set) var inBoard: [UInt8] = []
    public private(set) var drain = 0
    public internal(set) var entry: [Int] = []
    var dist: [Int32] = []
    var buckets: [[Int]] = Array(repeating: [], count: 6)
    var byColor: [[Int]?] = []

    // Builder's notes (levelSummary in JS).
    public var def: Difficulty?
    public var diff: String?
    public var seed: Int?
    public var plan: [Int]?
    public var nests: Int?
    public var small: Int?
    public var minNest: Int?
    public var maxNest: Int?
    public var botWin: Double?
    public var randWin: Double?
    public var randN: Int?
    public var tuneIters: Int?
    public var aim: Double?

    public var W: Int { art.W }
    public var H: Int { art.H }
    public var lock: Bool { art.lock }
    public var lockAt: Int { art.lockAt }

    public init(art: Art, slots: Int, lanes: [[NestSpec]]) {
        self.art = art
        self.slots = slots
        self.lanes = lanes
    }

    /// An independent copy. Routing borrows scratch buffers stored on the level (`dist`, `buckets`) and fills a cache
    /// (`byColor`) as it goes, so two threads must never simulate on the same Level: anything that solves or plays
    /// out a board off the main thread (the Wise Owl) works on a copy.
    public func copy() -> Level {
        let c = Level(art: art, slots: slots, lanes: lanes)
        c.hasNav = hasNav
        c.NW = NW
        c.NH = NH
        c.inBoard = inBoard
        c.drain = drain
        c.entry = entry
        c.dist = dist
        c.buckets = buckets
        c.byColor = byColor
        c.def = def
        c.diff = diff
        c.seed = seed
        c.plan = plan
        c.nests = nests
        c.small = small
        c.minNest = minNest
        c.maxNest = maxNest
        c.botWin = botWin
        c.randWin = randWin
        c.randN = randN
        c.tuneIters = tuneIters
        c.aim = aim
        return c
    }

    /// JS navSetup.
    public func navSetup() {
        NW = W + MG.l + MG.r
        NH = H + MG.t + MG.b
        let n = NW * NH
        dist = [Int32](repeating: 0, count: n)
        buckets = Array(repeating: [], count: 6)
        inBoard = [UInt8](repeating: 0, count: n)
        for r in MG.t..<(MG.t + H) {
            for c in MG.l..<(MG.l + W) { inBoard[r * NW + c] = 1 }
        }
        drain = (MG.t + H + 3) * NW + NW / 2
        hasNav = true
        placeEntries()
    }

    /// Extra Slot: change the number of holding slots (and where each slot's critters come out).
    public func setSlots(_ n: Int) {
        slots = n
        if hasNav { placeEntries() }
    }

    private func placeEntries() {
        entry = (0..<slots).map { k in
            (NH - 1) * NW + Int(((Double(k) + 0.5) / Double(slots) * Double(NW)).rounded(.down))
        }
    }

    @inline(__always) public func boardToNav(_ i: Int) -> Int {
        (i / W + MG.t) * NW + (i % W) + MG.l
    }

    @inline(__always) public func navToBoard(_ n: Int) -> Int {
        let r = n / NW - MG.t, c = n % NW - MG.l
        return (r < 0 || c < 0 || r >= H || c >= W) ? -1 : r * W + c
    }

    /// Cells of one color in pickup order (magic wand).
    func colorOrder(_ col: Int) -> [Int] {
        if byColor.count <= col { byColor += Array(repeating: nil, count: col + 1 - byColor.count) }
        if let a = byColor[col] { return a }
        var a: [Int] = []
        for i in art.cells.indices where Int(art.cells[i]) == col { a.append(i) }
        let key = art.key
        a.sort { key[$0] < key[$1] }
        byColor[col] = a
        return a
    }

    /// What a saved or shipped board needs to be rebuilt (JS levelSummary).
    public var summary: LevelSummary {
        LevelSummary(lanes: lanes, plan: plan, nests: nests, small: small, minNest: minNest, maxNest: maxNest,
                     botWin: botWin, randWin: randWin, randN: randN, tuneIters: tuneIters, lock: lock)
    }
}

/// A finished board's lanes plus the builder's measurements. Shipped boards are stored in this form.
public struct LevelSummary: Codable, Equatable, Sendable {
    public var lanes: [[NestSpec]]
    public var plan: [Int]?
    public var nests: Int?
    public var small: Int?
    public var minNest: Int?
    public var maxNest: Int?
    public var botWin: Double?
    public var randWin: Double?
    public var randN: Int?
    public var tuneIters: Int?
    public var lock: Bool?
    public var seed: Int?

    public init(lanes: [[NestSpec]], plan: [Int]? = nil, nests: Int? = nil, small: Int? = nil, minNest: Int? = nil,
                maxNest: Int? = nil, botWin: Double? = nil, randWin: Double? = nil, randN: Int? = nil,
                tuneIters: Int? = nil, lock: Bool? = nil, seed: Int? = nil) {
        self.lanes = lanes
        self.plan = plan
        self.nests = nests
        self.small = small
        self.minNest = minNest
        self.maxNest = maxNest
        self.botWin = botWin
        self.randWin = randWin
        self.randN = randN
        self.tuneIters = tuneIters
        self.lock = lock
        self.seed = seed
    }
}

/// Rebuild a level object from stored lanes (shipped boards, or a background build's result). JS assembleLevel.
public func assembleLevel(base: LevelBase, diffKey: String, seed: Int, summary b: LevelSummary,
                          aim: Double? = nil) -> Level {
    var def = Difficulty.named(diffKey)
    var base = base
    if let lock = b.lock { base.lock = lock }
    def.lock = base.lock
    let art = Art(base, slots: def.slots)
    let lv = Level(art: art, slots: def.slots, lanes: b.lanes)
    lv.def = def
    lv.diff = diffKey
    lv.seed = b.seed ?? seed
    lv.plan = b.plan
    lv.nests = b.nests
    lv.small = b.small
    lv.minNest = b.minNest
    lv.maxNest = b.maxNest
    lv.botWin = b.botWin
    lv.randWin = b.randWin
    lv.randN = b.randN
    lv.tuneIters = b.tuneIters
    lv.aim = aim
    lv.navSetup()
    return lv
}
