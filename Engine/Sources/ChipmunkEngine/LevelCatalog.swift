import Foundation

/// Every picture in the game. The original 170 Level Play boards and Coin Mining come from the web version
/// (tools/export_levels.sh writes Resources/levels.json); new packs made from clipart by tools/make_pack.py come from
/// Resources/boards.json and follow them as Level Play boards 171 on.
///
/// Board numbering follows the web game's level index `i` (0-based): Level Play boards are 0..<170 (pack order),
/// Coin Mining pictures follow at 170..<190. A board's challenge, seed and aim come from that index, exactly as the
/// page's `dOf`, `seedFor` and `aimFor` do, so the same index builds the same board in both versions.
///
/// Packs downloaded after the app shipped (BoardPacks) come after all of those. The player's place in Level Play is
/// that index too, so boards are only ever added at the end: never reorder, remove or insert packs in boards.json
/// once a build with it has shipped, and never add bundled packs once downloaded packs exist, except published
/// packs (by their published id, in published order, right after the existing ones), which then aren't downloaded
/// again. CatalogTests pins the bundled order.
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
    /// Packs made from clipart (Resources/boards.json), played after the original ones.
    public private(set) var newPacks: [Pack] = []
    /// Original boards redrawn from clipart (boards.json "replace", keyed by the original board's id). The board
    /// keeps its place, pack and number; only the picture (and so its id) changes. Coin Mining is unaffected.
    public private(set) var replacements: [String: Picture] = [:]
    /// Packs downloaded after the app shipped (BoardPacks), played after the bundled ones, in the order taken.
    public private(set) var downloaded: [Pack] = []

    private enum CodingKeys: String, CodingKey {
        case format, source, packSize, packBonus, rampN, packs, paradise, baked
    }

    private struct NewBoards: Decodable {
        let packs: [Pack]
        let replace: [String: Picture]?
    }

    /// The catalog that ships inside the engine.
    public static func bundled() throws -> LevelCatalog {
        guard let url = Bundle.module.url(forResource: "levels", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        var c = try JSONDecoder().decode(LevelCatalog.self, from: Data(contentsOf: url))
        if let extra = Bundle.module.url(forResource: "boards", withExtension: "json") {
            let nb = try JSONDecoder().decode(NewBoards.self, from: Data(contentsOf: extra))
            c.newPacks = nb.packs
            c.replacements = nb.replace ?? [:]
        }
        return c
    }

    // MARK: - Level Play

    /// Every Level Play pack in play order: the original ones, the bundled new ones, then downloaded ones (with any
    /// redrawn boards in place).
    public var allPacks: [Pack] {
        let all = packs + newPacks + downloaded
        return replacements.isEmpty ? all : all.map { p in
            Pack(id: p.id, name: p.name, levels: p.levels.map { replacements[$0.id] ?? $0 })
        }
    }

    /// Ids of the packs inside the app (a downloaded pack with one of these ids is already here).
    public var bundledPackIDs: Set<String> { Set((packs + newPacks).map(\.id)) }

    /// This catalog plus downloaded pack files, in the order given (the ledger's). Each file's pack goes on the end;
    /// its `replace` swaps pictures in place (a replacement naming no board here is ignored). A pack already bundled is
    /// skipped. A pack whose board ids clash with boards already here is refused, and so is every file after it
    /// (nothing may skip ahead of a missing pack). Returns the new catalog and how many files it took.
    public func adding(_ files: [BoardPacks.File]) -> (catalog: LevelCatalog, taken: Int) {
        var c = self
        var ids = Set((packs + newPacks + downloaded).flatMap(\.levels).map(\.id)).union(replacements.values.map(\.id))
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

    /// Where Coin Mining's numbering starts: right after the original 170 boards, whatever packs are added after
    /// them, so Coin Mining boards and the daily puzzle stay the same.
    public var paradiseFrom: Int { packs.reduce(0) { $0 + $1.levels.count } }

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
