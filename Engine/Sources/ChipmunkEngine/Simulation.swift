import Foundation

/* ================= TIMED SIMULATION (the real game; animation and solver both run this) =================
   Clock: 10 ms ticks. Ants walk 16.875 cells per second (1 cell every 160/27 ticks). An ant is 8/3 of a cell long,
   and each nest releases one ant every 32 ticks (0.32 s), which puts consecutive ants 5.4 cells apart: 2 body lengths.
   An ant reserves its block on release, removes it on arrival, then carries it to the drain. Max 15 ants out per nest. */
public enum SIM {
    public static let TPC: Double = 160.0 / 27.0
    public static let REL: Double = 32
    public static let CREW = 15
    public static let BODY: Double = 8.0 / 3.0
    /// Seconds per tick.
    public static let tickSeconds = 0.01
}

/// Ants prefer cover inside the picture: a step beside a wall or block costs 1, a step across open ground costs 4.
public enum PATH {
    public static let EXPOSED: Int32 = 4
}

// MARK: - Navigation grid

/// pass[n]: an ant can stand here. wn[n]: how many of the 8 surrounding cells are wall (off the grid) or solid.
func initNav(_ lv: Level, _ s: inout State) {
    let NW = lv.NW, NH = lv.NH, n = NW * NH
    var pass = [UInt8](repeating: 0, count: n)
    var wn = [Int](repeating: 0, count: n)
    for k in 0..<n {
        let i = lv.navToBoard(k)
        pass[k] = (i < 0 || (s.b[i] == 0 && s.o[i] == 1)) ? 1 : 0
    }
    for r in 0..<NH {
        for c in 0..<NW {
            var w = 0
            for dr in -1...1 {
                for dc in -1...1 {
                    if dr == 0 && dc == 0 { continue }
                    let rr = r + dr, cc = c + dc
                    if rr < 0 || cc < 0 || rr >= NH || cc >= NW || pass[rr * NW + cc] == 0 { w += 1 }
                }
            }
            wn[r * NW + c] = w
        }
    }
    s.pass = pass
    s.wn = wn
    s.hasNav = true
}

func openNav(_ lv: Level, _ s: inout State, _ i: Int) {
    if !s.hasNav { return }
    let NW = lv.NW, NH = lv.NH, k = lv.boardToNav(i)
    if s.pass[k] != 0 { return }
    s.pass[k] = 1
    let r = k / NW, c = k % NW
    for dr in -1...1 {
        for dc in -1...1 {
            if dr == 0 && dc == 0 { continue }
            let rr = r + dr, cc = c + dc
            if rr >= 0 && cc >= 0 && rr < NH && cc < NW { s.wn[rr * NW + cc] -= 1 }
        }
    }
}

@inline(__always) func stepCost(_ lv: Level, _ s: State, _ j: Int) -> Int32 {
    lv.inBoard[j] != 0 && s.wn[j] == 0 ? PATH.EXPOSED : 1
}

let UNREACHED = Int32.max

/// Lowest-cost distance field from root (Dial's bucket queue), stopping once `stop` is settled.
/// Leaves the field in lv.dist for walk().
@discardableResult
func route(_ lv: Level, _ s: State, _ root: Int, _ stop: Int) -> Int32 {
    let NW = lv.NW, NH = lv.NH
    var dist = lv.dist
    lv.dist = []
    var B = lv.buckets
    lv.buckets = []
    defer {
        lv.dist = dist
        lv.buckets = B
    }
    let NB = B.count
    for k in dist.indices { dist[k] = UNREACHED }
    for k in 0..<NB { B[k].removeAll(keepingCapacity: true) }
    dist[root] = 0
    B[0].append(root)
    var cur: Int32 = 0
    var pending = 1
    while pending > 0 {
        let bi = Int(cur) % NB
        while let i = B[bi].popLast() {
            pending -= 1
            if dist[i] != cur { continue }
            if i == stop { return cur }
            let r = i / NW, c = i % NW
            for k in 0..<4 {
                let j: Int
                if k == 0 { if r == 0 { continue }; j = i - NW }
                else if k == 1 { if r == NH - 1 { continue }; j = i + NW }
                else if k == 2 { if c == 0 { continue }; j = i - 1 }
                else { if c == NW - 1 { continue }; j = i + 1 }
                if s.pass[j] == 0 { continue }
                let nd = cur + stepCost(lv, s, j)
                if nd < dist[j] {
                    dist[j] = nd
                    B[Int(nd) % NB].append(j)
                    pending += 1
                }
            }
        }
        cur += 1
    }
    return -1
}

/// Follow the field from start back to root. Among equally cheap steps: keep going straight, then take cover.
/// On the apron, vertical steps win. Every candidate step is equally cheap, so this never changes a trip's length.
func walk(_ lv: Level, _ s: State, _ start: Int) -> [Int] {
    let NW = lv.NW, NH = lv.NH, dist = lv.dist, apron = (MG.t + lv.H) * NW
    var path = [start]
    var cur = start, dir = -1, guardCount = NW * NH
    let D = [-NW, NW, -1, 1]
    if dist[start] == UNREACHED { return path }
    while dist[cur] > 0 && guardCount != 0 {
        guardCount -= 1
        let need = dist[cur] - stepCost(lv, s, cur)
        var best = -1, bs = -1, bd = -1
        let r = cur / NW, c = cur % NW
        for k in 0..<4 {
            if (k == 0 && r == 0) || (k == 1 && r == NH - 1) || (k == 2 && c == 0) || (k == 3 && c == NW - 1) { continue }
            let j = cur + D[k]
            if dist[j] != need { continue }
            let sc = (k == dir ? 2 : 0) + (s.wn[j] > 0 ? 1 : 0) + (k < 2 && j >= apron ? 3 : 0)
            if sc > bs {
                bs = sc
                best = j
                bd = k
            }
        }
        if best < 0 { break }
        cur = best
        dir = bd
        path.append(cur)
    }
    return path
}

/// Straight-line distance in cells (flying critters).
@inline(__always) func navDist(_ lv: Level, _ a: Int, _ b: Int) -> Double {
    let dx = Double(a % lv.NW - b % lv.NW), dy = Double(a / lv.NW - b / lv.NW)
    return (dx * dx + dy * dy).squareRoot()
}

// MARK: - Ants and the clock

/// One critter's trip: out along `p1` to block `i`, picked up at tick `ta`, home along `p2` by tick `th`.
public struct Ant: Equatable, Sendable {
    public var i: Int
    public var c: Int
    /// Id of the nest that sent it.
    public var id: Int
    /// Slot it came out of.
    public var k: Int
    public var t0: Double
    public var ta: Double
    public var th: Double
    public var picked: Bool
    /// Path cells in the navigation grid (lv.NW columns). Two points for a flying critter.
    public var p1: [Int]
    public var p2: [Int]?
    public var fly: Bool
    /// Ticks it stands at its block after reaching it, before setting off home (the walk home starts at `ta + hold`).
    public var hold: Double = 0
}

/// Hooks for animation: called as each critter sets off, picks up its block, and gets home.
public struct SimObserver {
    public var spawn: ((Ant) -> Void)?
    public var arrive: ((Ant) -> Void)?
    public var home: ((Ant) -> Void)?

    public init(spawn: ((Ant) -> Void)? = nil, arrive: ((Ant) -> Void)? = nil, home: ((Ant) -> Void)? = nil) {
        self.spawn = spawn
        self.arrive = arrive
        self.home = home
    }
}

/// The board plus every critter in flight. A value type: copying it is the JS `cloneSim`.
public struct Sim: Sendable {
    public var s: State
    public var ants: [Ant] = []
    /// Critters out per nest id.
    public var crew: [Int: Int] = [:]
    public var tick: Double = 0
    /// Ticks each critter stands at its block before heading home. The block still leaves the board on arrival, so the
    /// rules play out the same; only the trip home starts later. The game uses a short pause so the pickup reads; the
    /// level builder leaves it at 0, as in the web game.
    public var pickupPause: Double = 0

    public init(_ lv: Level) {
        s = initState(lv)
    }
}

func releasable(_ lv: Level, _ m: inout Sim) -> Bool {
    for n in m.s.sl where (m.crew[n.id] ?? 0) < SIM.CREW && canFeed(lv, &m.s, n) { return true }
    return false
}

public func simIdle(_ lv: Level, _ m: inout Sim) -> Bool {
    m.ants.isEmpty && !releasable(lv, &m)
}

func nextEvent(_ lv: Level, _ m: inout Sim) -> Double {
    var t = Double.infinity
    for a in m.ants {
        let e = a.picked ? a.th : a.ta
        if e < t { t = e }
    }
    if releasable(lv, &m) {
        let r = ((m.tick / SIM.REL).rounded(.down) + 1) * SIM.REL
        if r < t { t = r }
    }
    return t
}

/// Everything that happens on one tick, in a fixed order: arrivals, then homecomings, then releases.
/// Each ant's route is planned when it sets off, and its trip time is that route's length at walking speed.
func processTick(_ lv: Level, _ m: inout Sim, _ T: Double, _ cb: SimObserver?) {
    m.tick = T
    for x in m.ants.indices where !m.ants[x].picked && m.ants[x].ta <= T {
        m.ants[x].picked = true
        let ai = m.ants[x].i
        let at = lv.boardToNav(ai)
        if m.ants[x].fly {
            removeMagic(lv, &m.s, ai)
            m.ants[x].p2 = [at, lv.drain]
            m.ants[x].th = T + m.ants[x].hold + SIM.TPC * max(1, navDist(lv, at, lv.drain))
        } else {
            removeBlock(lv, &m.s, ai)
            route(lv, m.s, lv.drain, at)
            let p2 = walk(lv, m.s, at)
            m.ants[x].p2 = p2
            m.ants[x].th = T + m.ants[x].hold + SIM.TPC * Double(max(1, p2.count - 1))
        }
        cb?.arrive?(m.ants[x])
    }
    var k = m.ants.count - 1
    while k >= 0 {
        let a = m.ants[k]
        if a.picked && a.th <= T {
            m.crew[a.id, default: 0] -= 1
            m.ants.remove(at: k)
            cb?.home?(a)
        }
        k -= 1
    }
    if T.truncatingRemainder(dividingBy: SIM.REL) == 0 {
        var k = 0
        while k < m.s.sl.count {
            let n = m.s.sl[k]
            if (m.crew[n.id] ?? 0) >= SIM.CREW || !canFeed(lv, &m.s, n) {
                k += 1
                continue
            }
            let ex = lv.entry[n.k]
            let i: Int, p1: [Int], len: Double
            if n.w {
                i = claimMagic(lv, &m.s, n.c)
                let to = lv.boardToNav(i)
                p1 = [ex, to]
                len = navDist(lv, ex, to)
            } else {
                i = claim(lv, &m.s, n.c)
                route(lv, m.s, lv.boardToNav(i), ex)
                p1 = walk(lv, m.s, ex)
                len = Double(p1.count - 1)
            }
            let a = Ant(i: i, c: n.c, id: n.id, k: n.k, t0: T, ta: T + SIM.TPC * max(1, len), th: 0,
                        picked: false, p1: p1, p2: nil, fly: n.w, hold: m.pickupPause)
            m.ants.append(a)
            m.crew[n.id, default: 0] += 1
            cb?.spawn?(a)
            m.s.sl[k].r -= 1
            if m.s.sl[k].r == 0 {
                let done = m.s.sl.remove(at: k)
                nestDone(&m.s, done)
            } else {
                k += 1
            }
        }
    }
}

/// Run the clock up to tick T (everything due by then happens).
public func advanceTo(_ lv: Level, _ m: inout Sim, _ T: Double, _ cb: SimObserver? = nil) {
    while true {
        let e = nextEvent(lv, &m)
        if e > T { break }
        processTick(lv, &m, e, cb)
    }
    if T > m.tick && T != .infinity { m.tick = T }
}

/// Run the clock until nothing more can happen.
public func settleTimed(_ lv: Level, _ m: inout Sim, _ cb: SimObserver? = nil) {
    while true {
        let e = nextEvent(lv, &m)
        if e == .infinity { break }
        processTick(lv, &m, e, cb)
    }
}

// MARK: - For the game screen

/// Where a critter is at tick T, in navigation-grid cells (cell centers at x + 0.5, y + 0.5; y grows downward),
/// which way it is heading, and whether it is carrying its block home.
public struct AntPose: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var dx: Double
    public var dy: Double
    public var carrying: Bool
}

public func antPose(_ lv: Level, _ a: Ant, at T: Double) -> AntPose {
    let carrying = a.picked || T >= a.ta
    let path: [Int], t0: Double, t1: Double
    if carrying, let p2 = a.p2 {
        path = p2; t0 = a.ta + a.hold; t1 = a.th
    } else {
        path = a.p1; t0 = a.t0; t1 = a.ta
    }
    func cell(_ n: Int) -> (Double, Double) { (Double(n % lv.NW) + 0.5, Double(n / lv.NW) + 0.5) }
    if path.count < 2 {
        let (x, y) = cell(path.first ?? lv.drain)
        return AntPose(x: x, y: y, dx: 0, dy: -1, carrying: carrying)
    }
    let f = t1 > t0 ? min(1, max(0, (T - t0) / (t1 - t0))) : 1
    let s = f * Double(path.count - 1)
    let k = min(path.count - 2, Int(s))
    let u = s - Double(k)
    let (ax, ay) = cell(path[k]), (bx, by) = cell(path[k + 1])
    return AntPose(x: ax + (bx - ax) * u, y: ay + (by - ay) * u, dx: bx - ax, dy: by - ay, carrying: carrying)
}

/// No critter is out, none can be sent, and no nest can be tapped, yet blocks remain: the player is stuck.
public func isStuck(_ lv: Level, _ m: inout Sim) -> Bool {
    !m.s.won && simIdle(lv, &m) && legalMoves(lv, m.s).isEmpty
}

/// Every block is gone and every critter is home.
public func isCleared(_ m: Sim) -> Bool {
    m.s.won && m.ants.isEmpty
}

extension Level {
    /// RGB of color index c (1...).
    public func rgb(_ c: Int) -> UInt32 {
        c >= 1 && c <= art.chars.count ? PALETTE[art.chars[c - 1]] ?? 0x888888 : 0x888888
    }
}
