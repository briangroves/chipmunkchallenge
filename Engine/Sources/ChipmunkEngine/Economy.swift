import Foundation

/// What wins pay (rebalanced 2026-11-13). Level Play pays for how hard the board was, smoothly across the whole
/// skill range, and Coin Mining pays less than Level Play: it's the safe fallback (no hearts at stake), not the best
/// way to earn.
public enum Economy {
    /// A Coin Mining win.
    public static let miningCoins = 50
    /// A Level Play win on the first try without help pays this much more.
    public static let firstTryBonus = 0.5

    /// Coins for a Level Play (or daily puzzle) win on a board aimed at careful-player win rate `goal`: 50 at the
    /// warm-ups' 97%, 100 at 50%, 200 at the hardest 15%, in steps of 10.
    public static func levelCoins(goal: Double) -> Int {
        let g = min(Skill.easiest, max(Skill.hardest, goal))
        let c = g >= 0.5 ? 50 + 50 * (Skill.easiest - g) / (Skill.easiest - 0.5)
            : 100 + 100 * (0.5 - g) / (0.5 - Skill.hardest)
        return Int((c / 10).rounded()) * 10
    }
}
