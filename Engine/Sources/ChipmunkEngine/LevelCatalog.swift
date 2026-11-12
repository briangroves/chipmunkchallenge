import Foundation

/// Every picture in the game.
///
/// Level Play starts with the 50 boards in Resources/levelplay.json (Brian's 4- and 5-star picks); every board after
/// those is downloaded (BoardPacks, published by tools/publish_pack.py). A board's challenge, seed and aim come from
/// its place in Level Play (index `i`, 0-based), and that index is also the player's progress, so boards are only
/// ever added at the end: never reorder, remove or insert boards in levelplay.json once a build with it has
/// shipped; new boards go out as downloaded packs. BoardPackTests pins the bundled order.
///
/// The web game's original 170 boards and Coin Mining's 20 pictures (tools/export_levels.sh writes
/// Resources/levels.json) are kept for Coin Mining, whose board numbers follow the originals at 170..<190 exactly as
/// the page's `dOf`, `seedFor` and `aimFor` number them, and for the parity tests against the web game. The clipart
/// boards in Resources/boards.json no longer ship; the tools still read that file.
public struct LevelCatalog: Decodable, Sendable {
    public struct Picture: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let rows: [String]

        public init(id: String, name: String, rows: [String]) {
            self.id = id
            self.name = name
            self.rows = rows
        }
    }

    public struct Pack: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let levels: [Picture]

        public init(id: String, name: String, levels: [Picture]) {
            self.id = id
            self.name = name
            self.levels = levels
        }
    }

    public struct ParadisePicture: Decodable, Sendable {
        public let id: String
        public let name: String
        /// The same picture with a different background pattern per round.
        public let variants: [[String]]
    }

    public let format: Int
    /// SHA-256 of the HTML the pictures were exported from.
    public let source: String
    public let packSize: Int
    public let packBonus: Int
    public let rampN: Int
    public let packs: [Pack]
    public let paradise: [ParadisePicture]
    /// Pre-built boards, keyed "levelId|diffKey" (Food 1-5 on their ramp settings).
    public let baked: [String: LevelSummary]
    /// The boards Level Play starts with (Resources/levelplay.json).
    public private(set) var starterPacks: [Pack] = []
    /// Boards redrawn by a downloaded pack's "replace", keyed by the board's id. The board keeps its place, pack and
    /// number; only the picture (and so its id) changes.
    public private(set) var replacements: [String: Picture] = [:]
    /// Packs downloaded after the app shipped (BoardPacks), played after the bundled ones, in the order taken.
    public private(set) var downloaded: [Pack] = []

    private enum CodingKeys: String, CodingKey {
        case format, source, packSize, packBonus, rampN, packs, paradise, baked
    }

    private struct Starter: Decodable {
        let packs: [Pack]
    }

    /// The catalog that ships inside the engine.
    public static func bundled() throws -> LevelCatalog {
        guard let url = Bundle.module.url(forResource: "levels", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        var c = try JSONDecoder().decode(LevelCatalog.self, from: Data(contentsOf: url))
        guard let start = Bundle.module.url(forResource: "levelplay", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        c.starterPacks = try JSONDecoder().decode(Starter.self, from: Data(contentsOf: start)).packs
        return c
    }

    // MARK: - Level Play

    /// Every Level Play pack in play order: the starter packs, then downloaded ones (with any redrawn boards in place).
    public var allPacks: [Pack] {
        let all = starterPacks + downloaded
        return replacements.isEmpty ? all : all.map { p in
            Pack(id: p.id, name: p.name, levels: p.levels.map { replacements[$0.id] ?? $0 })
        }
    }

    /// Ids of the packs inside the app (a downloaded pack with one of these ids is already here).
    public var bundledPackIDs: Set<String> { Set(starterPacks.map(\.id)) }

    /// How many Level Play boards ship in the app.
    public var starterCount: Int { starterPacks.reduce(0) { $0 + $1.levels.count } }

    /// Level Play boards the daily puzzle draws its picture from: the bundled ones after the first five (so a pack
    /// arriving mid-day doesn't change today's puzzle).
    public var dailyPool: [Int] { Array(min(5, starterCount - 1)..<starterCount) }

    /// This catalog plus downloaded pack files, in the order given (the ledger's). Each file's pack goes on the end;
    /// its `replace` swaps pictures in place (a replacement naming no board here is ignored). A pack already bundled is
    /// skipped. A pack whose board ids clash with boards already here is refused, and so is every file after it
    /// (nothing may skip ahead of a missing pack). Returns the new catalog and how many files it took.
    public func adding(_ files: [BoardPacks.File]) -> (catalog: LevelCatalog, taken: Int) {
        var c = self
        var ids = Set((starterPacks + downloaded).flatMap(\.levels).map(\.id)).union(replacements.values.map(\.id))
        let bundled = bundledPackIDs
        var taken = 0
        for f in files {
            guard f.format <= BoardPacks.format, f.packs.count == 1 else { break }
            let pack = f.packs[0]
            if !bundled.contains(pack.id) {
                guard !c.downloaded.contains(where: { $0.id == pack.id }) else { break }
                let new = pack.levels.map(\.id)
                guard Set(new).count == new.count, ids.isDisjoint(with: new) else { break }
                ids.formUnion(new)
                c.downloaded.append(pack)
            }
            for (old, pic) in f.replace ?? [:] {
                guard ids.contains(old) || c.replacements[old] != nil else { continue }
                c.replacements[old] = pic
                ids.insert(pic.id)
            }
            taken += 1
        }
        return (c, taken)
    }

    /// Level Play boards in play order (index = board number - 1).
    public var levelPlay: [Picture] { allPacks.flatMap(\.levels) }

    /// Where Coin Mining's numbering starts: right after the web game's original 170 boards (no longer in Level Play),
    /// so Coin Mining boards stay the same.
    public var paradiseFrom: Int { packs.reduce(0) { $0 + $1.levels.count } }

    // MARK: - The web game's original boards (parity tests)

    /// Original board i (0..<170) as the web game builds it: its picture, challenge, seed and pre-built board.
    public func original(_ i: Int) -> (base: LevelBase, diffKey: String, seed: Int, baked: LevelSummary?, id: String) {
        let p = packs.flatMap(\.levels)[i]
        let key = diffKey(forBoard: i)
        let b = baked[p.id + "|" + key]
        return (levelBase(name: p.name, rows: p.rows, boardNumber: i + 1), key, b?.seed ?? (i + 1) * 1000 + 7, b, p.id)
    }

    /// Completion bonus for a pack (5,000 for 20 levels, scaled by size).
    public func bonus(forPack id: String) -> Int {
        let size = allPacks.first { $0.id == id }?.levels.count ?? packSize
        return JS.roundInt(Double(packBonus * size) / Double(packSize))
    }

    /// Challenge key for Level Play board index i: warm1...warm20, then lv21 on.
    public func diffKey(forBoard i: Int) -> String {
        i < 20 ? "warm\(i + 1)" : "lv\(i + 1)"
    }

    /// The picture plus this board's rocks and locked slot.
    public func base(forBoard i: Int) -> LevelBase {
        let p = levelPlay[i]
        return levelBase(name: p.name, rows: p.rows, boardNumber: i + 1)
    }

    /// The pre-built board for board i, if it ships one (only for the first attempt at the standard aim).
    public func baked(forBoard i: Int) -> LevelSummary? {
        baked[levelPlay[i].id + "|" + diffKey(forBoard: i)]
    }

    /// Seed for board index i. `attempt` counts from 1 and goes up each time the player asks for a fresh board.
    public func seed(forBoard i: Int, attempt: Int = 1) -> Int {
        if attempt == 1, i < paradiseFrom, let b = baked(forBoard: i), let s = b.seed { return s }
        return (i + 1) * 1000 + 7 + (attempt - 1)
    }

    // MARK: - Coin Mining (Acorn Paradise)

    /// Board for Coin Mining round r (0, 1, 2...): which picture, its rows this round, and its seed.
    /// Rounds cycle through the 20 pictures; each lap uses the next background variant. After the exported variants
    /// run out (260 rounds) the variants repeat.
    public func paradiseRound(_ r: Int) -> (index: Int, base: LevelBase, seed: Int) {
        let n = paradise.count
        let pic = paradise[r % n]
        let v = r / n
        let rows = pic.variants[v % pic.variants.count]
        let i = paradiseFrom + r % n
        return (i, LevelBase(name: pic.name, rows: rows), (i + 1) * 1000 + 7 + v)
    }

    // MARK: - Aim (the player's tailored challenge)

    /// The standard 💪 aim for a challenge: 1 ÷ its random-tapper target, to one decimal.
    public static func baseAim(_ diffKey: String) -> Double {
        JS.round(10 / Difficulty.named(diffKey).rtarget) / 10
    }

    /// The aim a build uses. `tailor` is the player's skill factor (1 = standard). Warm-up boards, Coin Mining and
    /// the daily puzzle always use the standard aim.
    public static func aim(_ diffKey: String, tailor: Double) -> Double {
        if diffKey == "paradise" || diffKey == "daily" || diffKey.hasPrefix("warm") { return baseAim(diffKey) }
        return min(300, max(1.1, JS.round(10 * tailor / Difficulty.named(diffKey).rtarget) / 10))
    }
}
