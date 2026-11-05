import Foundation

/// Every picture in the game, exported from the web version by tools/export_levels.sh into Resources/levels.json.
///
/// Board numbering follows the web game's level index `i` (0-based): Level Play boards are 0..<170 (pack order),
/// Coin Mining pictures follow at 170..<190. A board's challenge, seed and aim come from that index, exactly as the
/// page's `dOf`, `seedFor` and `aimFor` do, so the same index builds the same board in both versions.
public struct LevelCatalog: Decodable, Sendable {
    public struct Picture: Decodable, Sendable {
        public let id: String
        public let name: String
        public let rows: [String]
    }

    public struct Pack: Decodable, Sendable {
        public let id: String
        public let name: String
        public let levels: [Picture]
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

    /// The catalog that ships inside the engine.
    public static func bundled() throws -> LevelCatalog {
        guard let url = Bundle.module.url(forResource: "levels", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(LevelCatalog.self, from: Data(contentsOf: url))
    }

    // MARK: - Level Play

    /// Level Play boards in play order (index = board number - 1).
    public var levelPlay: [Picture] { packs.flatMap(\.levels) }

    public var paradiseFrom: Int { packs.reduce(0) { $0 + $1.levels.count } }

    /// Completion bonus for a pack (5,000 for 20 levels, scaled by size).
    public func bonus(forPack id: String) -> Int {
        let size = packs.first { $0.id == id }?.levels.count ?? packSize
        return JS.roundInt(Double(packBonus * size) / Double(packSize))
    }

    /// Challenge key for Level Play board index i: warm1...warm20, then lv21...lv170.
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
