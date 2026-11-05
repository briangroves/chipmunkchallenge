import ChipmunkEngine
import Foundation
import UIKit

/// What the slots and lanes show right now. Published only when it changes, so SwiftUI redraws them only then.
struct SideState: Equatable {
    struct SlotItem: Equatable {
        var c: Int
        var r: Int
        var key: Bool
        var magic: Bool
    }

    struct Lane: Equatable, Identifiable {
        var id: Int
        /// Front nest first, then up to three behind it (the fourth is the half-hidden preview).
        var nests: [NestSpec]
    }

    var slots: [SlotItem?] = []
    var lockedAt: Int?
    /// Slot columns the lanes line up with (the board's base slot count).
    var columns = 5
    var lanes: [Lane] = []
}

/// One board in play: loads (or builds) the board, runs the timed simulation, and takes the player's taps.
/// BoardView drives the clock every frame; SwiftUI shows the published state.
@MainActor
final class GameModel: ObservableObject {
    enum Status: Equatable {
        case building
        case playing
        case won
        case stuck
        case failed(String)
    }

    @Published private(set) var status: Status = .building
    @Published private(set) var boardIndex: Int
    @Published private(set) var title = ""
    @Published private(set) var subtitle = ""
    @Published var fast = false
    @Published private(set) var side = SideState()
    /// Bumped whenever a new board is ready (or restarts), so the board view repaints from scratch.
    @Published private(set) var boardVersion = 0
    /// The 3D scene playing over the stage (intro, lose, win), if any.
    @Published private(set) var scene: SceneRun?
    /// The win or stuck card is up (it appears as the scene fades).
    @Published private(set) var cardShown = false
    @Published private(set) var canUndo = false
    @Published private(set) var coins: Int
    /// What the last win paid.
    @Published private(set) var lastWin = Win(base: 0, bonus: 0)
    /// The win card's "Next time" choice (nil on warm-up boards).
    @Published private(set) var tailorPick: TailorPick?
    /// Three tries without a win: the next try gets a new, easier board.
    @Published private(set) var easeNext = false
    /// Blocks cleared, all time.
    @Published private(set) var lifetime: Int
    /// Board cell size in points, set by the layout (JS sizeBoard).
    var cellSize: CGFloat = 7.5

    let catalog: LevelCatalog
    private(set) var level: Level?
    /// The simulation. The board view reads it to draw; only this model changes it.
    private(set) var sim: Sim?
    /// Simulation clock, in ticks (10 ms each).
    private(set) var simT: Double = 0
    private var attempt = 1
    private var history: [Sim] = []
    private var firstTry = true
    private var tailor: Double
    private var tailorBefore: Double = 1
    private var failStreak = 0
    private var buildTask: Task<Void, Never>?
    private let tapFeedback = UIImpactFeedbackGenerator(style: .light)
    private let notify = UINotificationFeedbackGenerator()

    private static let boardKey = "native.boardIndex"
    static let continuePrice = 300

    struct SceneRun: Equatable {
        enum Kind { case intro, lose, win }
        let kind: Kind
        let id: Int
    }

    struct Win: Equatable {
        var base: Int
        var bonus: Int
    }

    /// Win-card difficulty picks (JS TAILOR).
    enum TailorPick: String, CaseIterable {
        case easier, same, tiny, harder
        var factor: Double {
            switch self {
            case .easier: return 1 / 1.15
            case .same: return 1
            case .tiny: return 1.05
            case .harder: return 1.15
            }
        }
    }

    private var sceneID = 0
    private let store = UserDefaults.standard
    private static let reduceMotion = { UIAccessibility.isReduceMotionEnabled }

    init() {
        catalog = try! LevelCatalog.bundled()
        coins = store.object(forKey: "native.coins") == nil ? 500 : store.integer(forKey: "native.coins")
        lifetime = store.integer(forKey: "native.lifetime")
        tailor = store.object(forKey: "native.tailor") == nil ? 1 : store.double(forKey: "native.tailor")
        let saved = UserDefaults.standard.integer(forKey: Self.boardKey)
        boardIndex = min(max(0, saved), 169)
        load(boardIndex)
    }

    // MARK: - Boards

    func load(_ i: Int, attempt: Int = 1) {
        buildTask?.cancel()
        boardIndex = i
        self.attempt = attempt
        UserDefaults.standard.set(i, forKey: Self.boardKey)
        let p = catalog.levelPlay[i]
        title = p.name
        subtitle = "Level \(i + 1)"
        status = .building
        cardShown = false
        easeNext = false
        firstTry = true
        history = []
        canUndo = false
        play(.intro)

        let base = catalog.base(forBoard: i)
        let key = catalog.diffKey(forBoard: i)
        let seed = catalog.seed(forBoard: i, attempt: attempt)
        let aim = LevelCatalog.aim(key, tailor: tailor)
        if attempt == 1, aim == LevelCatalog.baseAim(key), let baked = catalog.baked(forBoard: i) {
            start(assembleLevel(base: base, diffKey: key, seed: seed, summary: baked, aim: aim))
            return
        }
        buildTask = Task { [weak self] in
            let built = await Task.detached(priority: .userInitiated) { () -> LevelBox in
                var o = BuildOptions.game
                o.aim = aim
                return LevelBox(generateLevel(base: base, seed: seed, diffKey: key, options: o))
            }.value
            guard let self, !Task.isCancelled, self.boardIndex == i else { return }
            if let lv = built.level {
                self.start(lv)
            } else {
                self.status = .failed("Couldn't build a board from this picture.")
            }
        }
    }

    private func start(_ lv: Level) {
        level = lv
        restart()
    }

    /// Play the same board again from the start.
    func restart() {
        guard let lv = level else { return }
        if let s = lv.def?.slots, lv.slots != s { lv.setSlots(s) }
        sim = Sim(lv)
        simT = 0
        status = .playing
        cardShown = false
        history = []
        canUndo = false
        tapFeedback.prepare()
        boardVersion += 1
        refreshSide()
        #if DEBUG
        // `-scene win|lose|card-win|card-stuck` jumps straight to a scene or card (for comparing against the web).
        switch UserDefaults.standard.string(forKey: "scene") {
        case "win": status = .won; payOut(lv); play(.win)
        case "lose": status = .stuck; play(.lose)
        case "card-win": status = .won; payOut(lv); scene = nil; cardShown = true
        case "card-stuck": status = .stuck; scene = nil; cardShown = true
        default: break
        }
        #endif
    }

    /// The card's Restart: a fresh try at the same board (or a new, easier one after three tries without a win).
    func retry() {
        firstTry = false
        if easeNext { load(boardIndex, attempt: attempt + 1); return }
        restart()
    }

    /// The top bar's restart button counts as a failed try.
    func restartButton() {
        firstTry = false
        noteFailure()
        if easeNext { load(boardIndex, attempt: attempt + 1); return }
        restart()
    }

    private func noteFailure() {
        failStreak += 1
        if failStreak >= 3 {
            failStreak = 0
            tailor = Self.clampT(tailor / 1.15)
            store.set(tailor, forKey: "native.tailor")
            easeNext = true
        }
    }

    private static func clampT(_ t: Double) -> Double { min(6, max(0.35, t)) }

    /// A different board from the same picture.
    func newBoard() { load(boardIndex, attempt: attempt + 1) }

    func next() { load(min(boardIndex + 1, catalog.levelPlay.count - 1)) }

    func previous() { load(max(boardIndex - 1, 0)) }

    // MARK: - Playing

    /// Move the clock forward by `dt` seconds of real time.
    func advance(by dt: TimeInterval) {
        guard status == .playing, let lv = level, var m = sim else { return }
        simT += min(dt, 0.1) / SIM.tickSeconds * (fast ? 3 : 1)
        advanceTo(lv, &m, simT)
        #if DEBUG
        // Launch with `-autoplay YES` to watch the board play its own stored solution (for testing).
        if UserDefaults.standard.bool(forKey: "autoplay"), canTap(lv, m.s),
           let l = planFrom(lv, m.s.lp)?.first, legalMoves(lv, m.s).contains(l) {
            ChipmunkEngine.tap(lv, &m.s, l)
        }
        #endif
        let before = sim?.s.left ?? m.s.left
        sim = m
        if m.s.left < before {
            lifetime += before - m.s.left
            store.set(lifetime, forKey: "native.lifetime")
        }
        refreshSide()
        if isCleared(m) {
            status = .won
            payOut(lv)
            notify.notificationOccurred(.success)
            play(.win)
        } else if isStuck(lv, &m) {
            status = .stuck
            firstTry = false
            noteFailure()
            notify.notificationOccurred(.error)
            play(.lose)
        }
    }

    /// JS payOut, without packs, hearts or mystery boxes yet.
    private func payOut(_ lv: Level) {
        let c = lv.botWin
        let base: Int = lv.diff == "paradise" ? 100
            : c == nil ? 100 : Int(JSRound(100 * min(2.5, max(0.6, 0.3 / max(c!, 0.01))) / 10)) * 10
        let bonus = firstTry ? Int(JSRound(Double(base) * 0.5)) : 0
        lastWin = Win(base: base, bonus: bonus)
        failStreak = 0
        easeNext = false
        if lv.diff?.hasPrefix("warm") == true {
            tailorPick = nil
        } else {
            tailorBefore = tailor
            pickTailor(firstTry ? .tiny : .same)
        }
        coins += base + bonus
        store.set(coins, forKey: "native.coins")
    }

    /// Win card choice: re-applies from the target before this win, so picks replace each other.
    func pickTailor(_ k: TailorPick) {
        tailorPick = k
        tailor = Self.clampT(tailorBefore * k.factor)
        store.set(tailor, forKey: "native.tailor")
    }

    // MARK: - Scenes

    private func play(_ kind: SceneRun.Kind) {
        if Self.reduceMotion() {
            scene = nil
            cardShown = kind != .intro
            return
        }
        sceneID += 1
        scene = SceneRun(kind: kind, id: sceneID)
    }

    /// The scene has played through (or was skipped): the card appears under it while it fades.
    func sceneFinished(_ run: SceneRun) {
        guard scene == run else { return }
        if run.kind != .intro { cardShown = true }
    }

    /// The scene has faded out.
    func sceneGone(_ run: SceneRun) {
        if scene == run { scene = nil }
    }

    /// Whether the intro may end (the board is built).
    var introReady: Bool { status != .building }

    /// The splash's small line: the pack name, or Coin Mining.
    var packLabel: String {
        if boardIndex >= catalog.paradiseFrom { return "⛏️ Coin Mining" }
        var k = boardIndex
        for p in catalog.packs {
            if k < p.levels.count { return p.name }
            k -= p.levels.count
        }
        return ""
    }

    // MARK: - Undo and continue

    func undo() {
        guard let m = history.popLast(), level != nil else { return }
        firstTry = false
        sim = m
        simT = m.tick
        canUndo = !history.isEmpty
        status = .playing
        cardShown = false
        scene = nil
        boardVersion += 1
        refreshSide()
    }

    /// After getting stuck: 300 coins empties 3 slots chosen at random and takes those nests' blocks off the board.
    func continueGame() {
        guard status == .stuck, coins >= Self.continuePrice, let lv = level, var m = sim else { return }
        coins -= Self.continuePrice
        store.set(coins, forKey: "native.coins")
        firstTry = false
        history.append(m)
        canUndo = true
        let before = m.s.left
        rescueSlots(lv, &m.s, RNG(seed: (Int(Date().timeIntervalSince1970 * 1000) & 0xFFFF) + history.count), 3)
        lifetime += before - m.s.left
        store.set(lifetime, forKey: "native.lifetime")
        sim = m
        status = .playing
        cardShown = false
        scene = nil
        boardVersion += 1
        tapFeedback.impactOccurred()
        refreshSide()
        if m.s.left == 0 {
            status = .won
            payOut(lv)
            cardShown = true
        }
    }

    /// Tap lane l: its front nest moves into a free slot. Returns false when that isn't possible right now.
    @discardableResult
    func tap(lane l: Int) -> Bool {
        guard status == .playing, let lv = level, var m = sim else { return false }
        guard legalMoves(lv, m.s).contains(l) else { return false }
        history.append(m)
        canUndo = true
        ChipmunkEngine.tap(lv, &m.s, l)
        sim = m
        tapFeedback.impactOccurred()
        tapFeedback.prepare()
        refreshSide()
        return true
    }

    private func refreshSide() {
        guard let lv = level, let m = sim else { return }
        var s = SideState()
        s.columns = lv.def?.slots ?? lv.slots
        s.slots = (0..<lv.slots).map { k in
            m.s.sl.first { $0.k == k }.map { SideState.SlotItem(c: $0.c, r: $0.r, key: $0.key, magic: $0.w) }
        }
        s.lockedAt = m.s.locked ? lv.lockAt : nil
        for (l, lane) in lv.lanes.enumerated() {
            let p = m.s.lp[l]
            if p >= lane.count { continue }   // an empty lane drops out; the rest slide together
            var nests = [lane[p]]
            var k = p + 1
            while k < lane.count && nests.count < 4 {
                if m.s.tk[l][k] == 0 { nests.append(lane[k]) }
                k += 1
            }
            s.lanes.append(SideState.Lane(id: l, nests: nests))
        }
        if s != side { side = s }
    }

    // MARK: - Looks

    /// RGB of color index c on this board.
    func hex(_ c: Int) -> UInt32 { level?.rgb(c) ?? 0x888888 }

    /// Difficulty tier (JS TIERS): acorn count from the careful player's win rate.
    var tier: Int? {
        guard let c = level?.botWin else { return nil }
        return c >= 0.5 ? 1 : c >= 0.35 ? 2 : c >= 0.22 ? 3 : c >= 0.12 ? 4 : 5
    }

    /// Difficulty shown to the player: acorns from the careful player's win rate (JS TIERS / acorns).
    var acorns: String {
        guard let c = level?.botWin else { return "–" }
        let n = c >= 0.5 ? 1 : c >= 0.35 ? 2 : c >= 0.22 ? 3 : c >= 0.12 ? 4 : 5
        return String(repeating: "🌰", count: n)
    }
}

/// Carries a built Level out of the background task (Level is a class the builder no longer touches).
private struct LevelBox: @unchecked Sendable {
    let level: Level?
    init(_ level: Level?) { self.level = level }
}
