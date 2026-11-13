import Foundation

/// Every picture in the game. Since 2026-11-13 Level Play is one flat run of boards from the new board maker
/// (Resources/boards.json "levels", then approved boards from the feed), and Coin Mining plays boards.json "mining".
/// There are no packs. The original web-game export (Resources/levels.json, grouped in the web game's packs) is kept
/// only for its numbering and the parity tests.
///
/// Board numbering follows the web game's level index `i` (0-based): the original boards were 0..<170,
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
    /// Level Play's boards from the new board maker (Resources/boards.json "levels"), in play order. Level Play is
    /// one long run of boards: there are no packs, pack names or pack rewards (2026-11-13).
    public private(set) var newBoards: [Picture] = []
    /// Original boards redrawn from clipart (boards.json "replace", keyed by the original board's id). The board
    /// keeps its place, pack and number; only the picture (and so its id) changes. Coin Mining is unaffected.
    public private(set) var replacements: [String: Picture] = [:]
    /// Boards approved in the Board Review app (the public feed, tools/daily/publish.py), played after all the others.
    /// The game ships a snapshot (Resources/approved-boards.json) and downloads newer copies with `merge(feed:)`.
    public private(set) var approvedBoards: [Picture] = []
    /// True when boards.json says the original 170 boards are out of Level Play (2026-11-12: only boards from the new
    /// board maker play). They stay in `packs` for Coin Mining's numbering, which still starts at 170.
    public var retireOriginals = false
    /// Coin Mining's boards from the new board maker (boards.json "mining", tools/make_mining.py). When there are
    /// any, Coin Mining plays them in place of the original pictures (`paradise`), which then only keep the numbering.
    public private(set) var miningBoards: [Picture] = []

    private enum CodingKeys: String, CodingKey {
        case format, source, packSize, packBonus, rampN, packs, paradise, baked
    }

    /// boards.json, approved-boards.json and the downloaded feed. Boards are a flat "levels" list; files written
    /// before 2026-11-13 grouped them in "packs", which are read as one list in order.
    private struct NewBoards: Decodable {
        var levels: [Picture]? = nil
        var packs: [Pack]? = nil
        var replace: [String: Picture]? = nil
        var retire: Bool? = nil
        var mining: [Picture]? = nil

        var boards: [Picture] { levels ?? (packs ?? []).flatMap(\.levels) }
    }

    /// The catalog that ships inside the engine.
    public static func bundled() throws -> LevelCatalog {
        guard let url = Bundle.module.url(forResource: "levels", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        var c = try JSONDecoder().decode(LevelCatalog.self, from: Data(contentsOf: url))
        if let extra = Bundle.module.url(forResource: "boards", withExtension: "json") {
            let nb = try JSONDecoder().decode(NewBoards.self, from: Data(contentsOf: extra))
            c.newBoards = nb.boards
            c.replacements = nb.replace ?? [:]
            c.retireOriginals = nb.retire ?? false
            c.miningBoards = nb.mining ?? []
        }
        // Boards approved in the Board Reviewer app, added by tools/daily/publish.py, played after all the others.
        if let approved = Bundle.module.url(forResource: "approved-boards", withExtension: "json"),
           let nb = try? JSONDecoder().decode(NewBoards.self, from: Data(contentsOf: approved)) {
            c.approvedBoards = nb.boards
        }
        return c
    }

    // MARK: - Approved boards feed

    /// Take a copy of the approved-boards feed if it extends what the game has: the feed only ever grows (boards are
    /// appended, never removed, changed or reordered, because a board's place sets its seed and challenge), so a copy
    /// is used only when the boards the game already has are its exact start. Returns how many boards it added.
    public mutating func merge(feed data: Data) -> Int {
        guard let nb = try? JSONDecoder().decode(NewBoards.self, from: data) else { return 0 }
        let new = nb.boards, old = approvedBoards
        guard new.count > old.count,
              zip(old, new).allSatisfy({ $0.id == $1.id }),
              new.allSatisfy({ $0.rows.count == 40 && $0.rows.allSatisfy { $0.count == 40 && $0.allSatisfy { PALETTE[paletteLetter($0)] != nil } } }) else { return 0 }
        approvedBoards = new
        return new.count - old.count
    }

    // MARK: - Level Play

    /// Level Play boards in play order (index = board number - 1): the new board maker's boards, then the approved
    /// ones from the feed. (With `retireOriginals` off, the original 170, with any redrawn boards, come first.)
    public var levelPlay: [Picture] {
        if retireOriginals { return newBoards + approvedBoards }
        let originals = packs.flatMap(\.levels).map { replacements[$0.id] ?? $0 }
        return originals + newBoards + approvedBoards
    }

    /// Where Coin Mining's numbering starts: right after the original 170 boards, whatever packs are added after
    /// them, so Coin Mining boards and the daily puzzle stay the same.
    public var paradiseFrom: Int { packs.reduce(0) { $0 + $1.levels.count } }

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
        if retireOriginals { return nil }
        return baked[levelPlay[i].id + "|" + diffKey(forBoard: i)]
    }

    /// Seed for board index i. `attempt` counts from 1 and goes up each time the player asks for a fresh board.
    public func seed(forBoard i: Int, attempt: Int = 1) -> Int {
        if attempt == 1, !retireOriginals, i < paradiseFrom, let b = baked(forBoard: i), let s = b.seed { return s }
        return (i + 1) * 1000 + 7 + (attempt - 1)
    }

    // MARK: - Coin Mining (Acorn Paradise)

    /// Board for Coin Mining round r (0, 1, 2...): which picture, its rows this round, and its seed.
    /// Rounds cycle through the 20 pictures; each lap uses the next background variant. After the exported variants
    /// run out (260 rounds) the variants repeat.
    /// The id of the Coin Mining picture at board index i (as `paradiseRound` returns it).
    public func paradiseID(forBoard i: Int) -> String {
        let k = i - paradiseFrom
        return miningBoards.isEmpty ? paradise[k].id : miningBoards[k].id
    }

    public func paradiseRound(_ r: Int) -> (index: Int, base: LevelBase, seed: Int) {
        if !miningBoards.isEmpty {
            // New-maker boards have one backdrop each; every lap plays them again on the next seed.
            let n = miningBoards.count, pic = miningBoards[r % n], v = r / n
            let i = paradiseFrom + r % n
            return (i, LevelBase(name: pic.name, rows: pic.rows), (i + 1) * 1000 + 7 + v)
        }
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
        if diffKey == "paradise" || diffKey == "daily" || diffKey.hasPrefix("warm") || diffKey.hasPrefix("skill") {
            return baseAim(diffKey)
        }
        return min(300, max(1.1, JS.round(10 * tailor / Difficulty.named(diffKey).rtarget) / 10))
    }
}
