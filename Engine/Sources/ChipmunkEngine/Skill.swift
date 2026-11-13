import Foundation

/// The player's skill in Level Play, which sets how hard each new level is (since 2026-11-13; before, the level's
/// number did). It is a careful player's win rate to aim the next level at: 0.97 is almost impossible to lose, 0.15
/// is the hardest. It never depends on how many boards there are.
///
/// - The first 5 levels stay at 0.97, unless the player asks for harder.
/// - A level won on the first try without a tool makes the next one a little harder; on the second try, a bit less.
/// - Using a tool (or Continue), or needing three tries or more, keeps the next level about the same.
/// - Five losses in a row make the next level a little easier. The level being played never gets easier.
/// - After each win the player can ask for the next level to be a little easier, the same, or a little harder than
///   the one just played; that replaces the automatic change.
public struct Skill: Codable, Equatable, Sendable {
    public static let easiest = 0.97, hardest = 0.15
    public static let warmups = 5
    public static let firstTryStep = 0.02, secondTryStep = 0.01
    public static let lossesToEase = 5, easeStep = 0.04
    public static let feedbackStep = 0.05

    public enum Feedback: String, Codable, CaseIterable, Sendable { case easier, same, harder }
    /// What a win did to the next level.
    public enum Change: Equatable, Sendable { case warmup, harder, same }

    /// The goal for the next new level.
    public var goal: Double
    /// Losses since the last win.
    public var lossStreak = 0

    public init(goal: Double = Skill.easiest) { self.goal = Self.clamp(goal) }

    public static func clamp(_ g: Double) -> Double { min(easiest, max(hardest, (g * 1000).rounded() / 1000)) }

    /// A loss (or a restart). Every fifth one in a row makes the next level a little easier; returns true then.
    public mutating func lost() -> Bool {
        lossStreak += 1
        guard lossStreak >= Self.lossesToEase else { return false }
        lossStreak = 0
        goal = Self.clamp(goal + Self.easeStep)
        return true
    }

    /// A win on level `level` (1 = the first), played at `boardGoal`, on try `tries`; `helped` if a tool or Continue
    /// was used on the winning try.
    public mutating func won(level: Int, boardGoal: Double, tries: Int, helped: Bool) -> Change {
        lossStreak = 0
        if level <= Self.warmups { return .warmup }
        guard !helped, tries <= 2 else { return .same }
        goal = Self.clamp(min(goal, boardGoal) - (tries == 1 ? Self.firstTryStep : Self.secondTryStep))
        return .harder
    }

    /// The player's own pick after a win, relative to the level just played (`auto` is the goal the win set).
    public static func picked(_ f: Feedback, boardGoal: Double, auto: Double) -> Double {
        switch f {
        case .easier: return clamp(max(auto, boardGoal + feedbackStep))
        case .same: return clamp(boardGoal)
        case .harder: return clamp(min(auto, boardGoal - feedbackStep))
        }
    }
}
