import Foundation

/// Three small hand-made boards played once, before Level 1, so a new player learns the game on boards that end in
/// under a minute (2026-11-27). Each one practises one how-to-play card:
///
/// 1. Tap a nest: five nests and five slots, so it can't be lost.
/// 2. Work from the outside in: every column starts with brown, which waits for the yellow petals, so the player digs
///    to a yellow nest before the slots fill.
/// 3. Keep a slot free: four rings and no blue nest in front, so tapping inner colors without a plan fills the slots.
///
/// They sit outside Level Play's numbering, so no board's seed, challenge or terrain moves.
public enum Practice {
    public struct Board: Sendable {
        public let name: String
        /// The idea it practises, shown on the splash and the win card.
        public let lesson: String
        public let hint: String
        public let rows: [String]
        /// Lanes front first, as (palette letter, critters).
        public let lanes: [[(Character, Int)]]
    }

    public static let boards: [Board] = [
        Board(name: "Apple", lesson: "Tap a nest",
              hint: "Tap the front nest of any column. Its chipmunks run out and eat blocks of their color.",
              rows: [
            "...........GG.....",
            "........G.GGG.....",
            "........G.GGGG....",
            "........GG.GG.....",
            ".......RGGR.......",
            ".....RRR..RRR.....",
            "....RRRRRRRRRR....",
            "...RRRRRRRRRRRR...",
            "..RRRRRRRRRRRRRR..",
            "..RRRRRRRRRRRRRR..",
            "..RRRRRRRRRRRRRR..",
            "..RRRRRRRRRRRRRR..",
            "..RRRRRRRRRRRRRR..",
            "..RRRRRRRRRRRRRR..",
            "...RRRRRRRRRRRR...",
            "....RRRRRRRRRR....",
            ".....RRRRRRRR.....",
            ".......RRRR......."
              ],
              lanes: [[("G", 17), ("R", 37)], [("R", 37)], [("R", 37)], [("R", 37)]]),
        Board(name: "Sunflower", lesson: "Work from the outside in",
              hint: "Brown chipmunks wait until the yellow petals around the middle are eaten. Dig through to a yellow nest before your slots fill up.",
              rows: [
            ".....YY....YY.....",
            "....YYYYYYYYYY....",
            "....YYYYYYYYYY....",
            "....YYYYYYYYYY....",
            ".YYYYYYYYYYYYYYYY.",
            "YYYYYYYNNNNYYYYYYY",
            "YYYYYYNNNNNNYYYYYY",
            ".YYYYNNNNNNNNYYYY.",
            ".YYYYNNNNNNNNYYYY.",
            ".YYYYNNNNNNNNYYYY.",
            ".YYYYNNNNNNNNYYYY.",
            "YYYYYYNNNNNNYYYYYY",
            "YYYYYYYNNNNYYYYYYY",
            ".YYYYYYYYYYYYYYYY.",
            "....YYYYYYYYYY....",
            "....YYYYYYYYYY....",
            "....YYYYYYYYYY....",
            ".....YY....YY....."
              ],
              lanes: [[("N", 8), ("N", 8), ("Y", 46)], [("N", 8), ("N", 7), ("Y", 46)], [("N", 7), ("N", 7), ("Y", 46)], [("N", 7), ("Y", 46)]]),
        Board(name: "Bright Gem", lesson: "Keep a slot free",
              hint: "Inner colors wait for the rings around them. Free the blue outside first, and keep a slot open while you dig.",
              rows: [
            "..................",
            ".......BBBB.......",
            "....BBBBBBBBBB....",
            "...BBBBCCCCBBBB...",
            "..BBBCCCCCCCCBBB..",
            "..BBCCCWWWWCCCBB..",
            "..BBCCWWWWWWCCBB..",
            ".BBCCWWWYYWWWCCBB.",
            ".BBCCWWYYYYWWCCBB.",
            ".BBCCWWYYYYWWCCBB.",
            ".BBCCWWWYYWWWCCBB.",
            "..BBCCWWWWWWCCBB..",
            "..BBCCCWWWWCCCBB..",
            "..BBBCCCCCCCCBBB..",
            "...BBBBCCCCBBBB...",
            "....BBBBBBBBBB....",
            ".......BBBB.......",
            ".................."
              ],
              lanes: [[("W", 14), ("Y", 6), ("B", 30)], [("Y", 6), ("W", 13), ("C", 20)], [("C", 20), ("W", 13), ("B", 29)], [("C", 20), ("B", 29)]]),
    ]

    public static var count: Int { boards.count }

    /// The base for practice board k (no rocks, lakes, burrows or lock).
    public static func base(_ k: Int) -> LevelBase { LevelBase(name: boards[k].name, rows: boards[k].rows) }

    /// The build key practice boards play on: the easiest skill setting (5 slots).
    public static let diffKey = Difficulty.skillKey(Skill.easiest)

    /// Board k's lanes as a stored board, with colors numbered as the picture numbers them.
    public static func summary(_ k: Int) -> LevelSummary {
        let art = Art(base(k), slots: Difficulty.named(diffKey).slots)
        let lanes = boards[k].lanes.map { lane in
            lane.map { NestSpec(c: (art.chars.firstIndex(of: $0.0) ?? 0) + 1, n: $0.1) }
        }
        return LevelSummary(lanes: lanes, nests: lanes.reduce(0) { $0 + $1.count })
    }

    /// Practice board k, ready to play, with a solution for the Wise Owl and autoplay (the boards are small, so the
    /// solver finds one at once).
    public static func level(_ k: Int) -> Level {
        let lv = assembleLevel(base: base(k), diffKey: diffKey, seed: 1 + k, summary: summary(k))
        lv.plan = solve(lv, Sim(lv), cap: 4000).path
        return lv
    }
}
