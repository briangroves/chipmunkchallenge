import Foundation

/// Seeded random numbers, bit-for-bit identical to the JavaScript `rngFrom` (mulberry32).
/// Level building depends on drawing the same numbers in the same order, so never reorder calls to `next()`.
public final class RNG {
    private var a: UInt32

    /// JS: `let a = seed >>> 0`
    public init(seed: Int) {
        a = UInt32(truncatingIfNeeded: seed)
    }

    /// A number in [0, 1).
    public func next() -> Double {
        a = a &+ 0x6D2B_79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }

    /// JS: `(rng() * n) | 0` for a non-negative n.
    public func int(_ n: Int) -> Int {
        Int(next() * Double(n))
    }
}

/// Small helpers that reproduce JavaScript number behaviour exactly.
enum JS {
    /// JS `Math.round`: nearest integer, halves round up (towards +∞).
    static func round(_ x: Double) -> Double {
        let f = x.rounded(.down)
        return x - f >= 0.5 ? f + 1 : f
    }

    static func roundInt(_ x: Double) -> Int {
        Int(round(x))
    }

    /// JS `Math.floor(x / y)` for integers stored as Int.
    static func trunc(_ x: Double) -> Int {
        Int(x.rounded(.towardZero))
    }
}
