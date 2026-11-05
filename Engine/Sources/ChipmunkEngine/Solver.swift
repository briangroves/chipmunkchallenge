import Foundation

/* ---- Solver on the timed simulation ----
   First it tries the stored plan from wherever the player is: the untapped nests, taken in the plan's order,
   always form a legal order. If that still clears the board, that's the answer. Otherwise a depth-first search
   (plan's next move first, then the careful player's preferences) with a memo of dead positions. */

/// The plan's remaining lane taps, given how far into each lane the player has tapped.
public func planFrom(_ lv: Level, _ lp: [Int]) -> [Int]? {
    guard let plan = lv.plan else { return nil }
    var cnt = Array(repeating: 0, count: lv.lanes.count)
    var out: [Int] = []
    for l in plan {
        if cnt[l] < lp[l] { cnt[l] += 1 } else { out.append(l) }
    }
    return out
}

func tryOrder(_ lv: Level, _ m0: Sim, _ order: [Int]) -> Bool {
    var m = m0
    settleTimed(lv, &m)
    for l in order {
        if m.s.left == 0 { break }
        if !canTap(lv, m.s) || m.s.lp[l] >= lv.lanes[l].count { return false }
        tap(lv, &m.s, l)
        settleTimed(lv, &m)
    }
    return m.s.left == 0
}

public struct Solution: Sendable {
    /// Lane taps that clear the board from the given position, or nil if none was found.
    public var path: [Int]?
    public var nodes: Int
    /// The search hit its node cap before finding an answer (the position may still be winnable).
    public var aborted: Bool
    public var ms: Double
    public var via: String
}

public func solve(_ lv: Level, _ m0: Sim, cap: Int = 400) -> Solution {
    let t0 = Date()
    let elapsed = { Date().timeIntervalSince(t0) * 1000 }
    if let pl = planFrom(lv, m0.s.lp), tryOrder(lv, m0, pl) {
        return Solution(path: pl, nodes: 1, aborted: false, ms: elapsed(), via: "plan")
    }
    var nodes = 0
    var aborted = false
    var dead = Set<StateKey>()

    func pref(_ m: Sim, _ l: Int) -> Double {
        let n = lv.lanes[l][m.s.lp[l]], reach = m.s.hp[n.c].count
        return reach >= n.n ? 2 : reach > 0 ? 1 + Double(reach) / Double(n.n) * 0.5 : 0
    }

    func rec(_ m: Sim) -> [Int]? {
        if m.s.left == 0 { return [] }
        let moves0 = legalMoves(lv, m.s)
        if moves0.isEmpty { return nil }
        let nx = planFrom(lv, m.s.lp)?.first
        // Plan's move first, then preferred; stable (keeps lane order among equals) like the JS sort.
        let moves = moves0.enumerated().map { (idx: $0.offset, l: $0.element, isNx: $0.element == nx, p: pref(m, $0.element)) }
            .sorted { a, b in
                if a.isNx != b.isNx { return a.isNx }
                if a.p != b.p { return a.p > b.p }
                return a.idx < b.idx
            }
            .map(\.l)
        for mv in moves {
            nodes += 1
            if nodes > cap {
                aborted = true
                return nil
            }
            var m2 = m
            tap(lv, &m2.s, mv)
            settleTimed(lv, &m2)
            let k = StateKey(m2.s)
            if dead.contains(k) { continue }
            if let r = rec(m2) { return [mv] + r }
            if aborted { return nil }
            dead.insert(k)
        }
        return nil
    }

    var m = m0
    settleTimed(lv, &m)
    let path = rec(m)
    return Solution(path: path, nodes: nodes, aborted: path == nil && aborted, ms: elapsed(), via: "search")
}
