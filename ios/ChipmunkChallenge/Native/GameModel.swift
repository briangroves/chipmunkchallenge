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
    /// Board cell size in points, set by the layout (JS sizeBoard).
    var cellSize: CGFloat = 7.5

    let catalog: LevelCatalog
    private(set) var level: Level?
    /// The simulation. The board view reads it to draw; only this model changes it.
    private(set) var sim: Sim?
    /// Simulation clock, in ticks (10 ms each).
    private(set) var simT: Double = 0
    private var attempt = 1
    private var buildTask: Task<Void, Never>?
    private let tapFeedback = UIImpactFeedbackGenerator(style: .light)
    private let notify = UINotificationFeedbackGenerator()

    private static let boardKey = "native.boardIndex"

    init() {
        catalog = try! LevelCatalog.bundled()
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

        let base = catalog.base(forBoard: i)
        let key = catalog.diffKey(forBoard: i)
        let seed = catalog.seed(forBoard: i, attempt: attempt)
        let aim = LevelCatalog.aim(key, tailor: 1)
        if attempt == 1, let baked = catalog.baked(forBoard: i) {
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
        tapFeedback.prepare()
        boardVersion += 1
        refreshSide()
    }

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
        sim = m
        refreshSide()
        if isCleared(m) {
            status = .won
            notify.notificationOccurred(.success)
        } else if isStuck(lv, &m) {
            status = .stuck
            notify.notificationOccurred(.error)
        }
    }

    /// Tap lane l: its front nest moves into a free slot. Returns false when that isn't possible right now.
    @discardableResult
    func tap(lane l: Int) -> Bool {
        guard status == .playing, let lv = level, var m = sim else { return false }
        guard legalMoves(lv, m.s).contains(l) else { return false }
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
