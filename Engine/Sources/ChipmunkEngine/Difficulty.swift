import Foundation

/// A challenge setting (JS `DIFF`): slot and lane counts, nest sizes, and the win rates the builder aims for.
public struct Difficulty: Codable, Equatable, Sendable {
    public var label: String
    public var slots: Int
    public var lanes: Int
    public var cmin: Int
    public var cmax: Int
    public var target: Double
    /// Random-tapper win rate to aim for (the 💪 score is 1 ÷ this).
    public var rtarget: Double
    /// Upper bound on the careful player's win rate.
    public var ctarget: Double?
    /// Careful player's win rate, aimed at from both sides.
    public var cgoal: Double?
    /// 0–1: how strongly the build prefers colors with only a few blocks in reach.
    public var pressure: Double
    /// Set from the level base when building (JS `def = {...base, ...DIFF[key]}`).
    public var lock: Bool = false

    public init(label: String, slots: Int, lanes: Int, cmin: Int, cmax: Int, target: Double, rtarget: Double,
                ctarget: Double? = nil, cgoal: Double? = nil, pressure: Double) {
        self.label = label
        self.slots = slots
        self.lanes = lanes
        self.cmin = cmin
        self.cmax = cmax
        self.target = target
        self.rtarget = rtarget
        self.ctarget = ctarget
        self.cgoal = cgoal
        self.pressure = pressure
    }

    public static let easy = Difficulty(label: "Easy", slots: 5, lanes: 3, cmin: 20, cmax: 45, target: 0.8,
                                        rtarget: 0.7, pressure: 0)
    /// Puzzle mode: random taps win ~2%, a careful greedy player ~40% or less.
    public static let normal = Difficulty(label: "Normal", slots: 5, lanes: 4, cmin: 12, cmax: 26, target: 0.4,
                                          rtarget: 0.01, ctarget: 0.3, pressure: 1)
    /// Acorn Paradise (Coin Mining): careful player ~70%, random taps still mostly lose.
    public static let paradise = Difficulty(label: "Paradise", slots: 5, lanes: 4, cmin: 15, cmax: 35, target: 0.7,
                                            rtarget: 0.15, cgoal: 0.7, pressure: 0)
    public static let hard = Difficulty(label: "Hard", slots: 5, lanes: 4, cmin: 12, cmax: 30, target: 0.12,
                                        rtarget: 0.1, pressure: 1)

    /// The Level Play ramp: board n (1...170) has its own careful-player target, ~97% on boards 1-5 easing to ~25%.
    public static let rampN = 170
    static let rampTop = 0.97, rampEnd = 0.25

    public static func rampGoal(_ n: Int) -> Double {
        if n > rampN { return lateGoal(n) }
        return n <= 5 ? rampTop : rampTop - (rampTop - rampEnd) * pow(min(1, Double(n - 5) / Double(rampN - 5)), 0.7)
    }

    /// Boards after 170 keep getting slowly harder, one steady climb (no packs): from 42% just past 170 to 16% at
    /// board 1000, and 16% from then on.
    static func lateGoal(_ n: Int) -> Double {
        let overall = min(1, Double(n - rampN - 1) / 829)
        return 0.42 - 0.26 * overall
    }

    /// Board n of the Level Play ramp. Food keeps the key names warm1...warm20; later boards are lv21 on. Past 170
    /// the nest sizes and pressure stay at board 170's, and the target follows `lateGoal`.
    public static func ramp(_ n: Int) -> Difficulty {
        let u = n <= 5 ? 0 : min(1, Double(n - 5) / Double(rampN - 5))
        let cg = rampGoal(n)
        let rt = n <= 5 ? 0.6 : max(0.01, JS.round(0.6 * pow(1 - u, 3) * 1000) / 1000)
        let pr = JS.round(min(1, max(0, (u - 0.15) / 0.4)) * 100) / 100
        return Difficulty(label: "Level \(n)", slots: 5, lanes: 4, cmin: JS.roundInt(22 - 10 * u),
                          cmax: JS.roundInt(40 - 14 * u), target: cg, rtarget: rt, cgoal: JS.round(cg * 1000) / 1000,
                          pressure: pr)
    }

    public static func rampKey(_ n: Int) -> String { n <= 20 ? "warm\(n)" : "lv\(n)" }

    /// Level Play's challenge since 2026-11-13: set by the player's skill (`Skill`), not by the board's number. `goal`
    /// is the careful player's win rate, from 0.97 (almost impossible to lose) down to 0.15. Nest sizes, the random
    /// tapper's target and the color pressure follow the goal as they did on the old ramp, so a goal plays like the
    /// ramp board that had it; below the ramp's 25% only the goal keeps falling.
    public static func skill(_ goal: Double) -> Difficulty {
        let g = min(Skill.easiest, max(Skill.hardest, goal))
        let u = g >= rampEnd ? pow((rampTop - g) / (rampTop - rampEnd), 1 / 0.7) : 1
        let rt = u == 0 ? 0.6 : max(0.01, JS.round(0.6 * pow(1 - u, 3) * 1000) / 1000)
        let pr = JS.round(min(1, max(0, (u - 0.15) / 0.4)) * 100) / 100
        return Difficulty(label: "Skill \(Int((g * 100).rounded()))", slots: 5, lanes: 4, cmin: JS.roundInt(22 - 10 * u),
                          cmax: JS.roundInt(40 - 14 * u), target: g, rtarget: rt, cgoal: JS.round(g * 1000) / 1000,
                          pressure: pr)
    }

    /// The build key for a skill goal ("skill970" for 0.97).
    public static func skillKey(_ goal: Double) -> String {
        "skill\(Int((min(Skill.easiest, max(Skill.hardest, goal)) * 1000).rounded()))"
    }

    /// Extra settings registered at run time (the daily puzzle's).
    nonisolated(unsafe) public static var custom: [String: Difficulty] = [:]

    public static func named(_ key: String) -> Difficulty {
        if let d = custom[key] { return d }
        switch key {
        case "easy": return .easy
        case "normal": return .normal
        case "paradise": return .paradise
        case "hard": return .hard
        default:
            if key.hasPrefix("warm"), let n = Int(key.dropFirst(4)) { return ramp(n) }
            if key.hasPrefix("lv"), let n = Int(key.dropFirst(2)) { return ramp(n) }
            if key.hasPrefix("skill"), let n = Int(key.dropFirst(5)) { return skill(Double(n) / 1000) }
            preconditionFailure("Unknown difficulty \(key)")
        }
    }
}

/// Smallest nest the builder makes.
public let MIN_NEST = 5
