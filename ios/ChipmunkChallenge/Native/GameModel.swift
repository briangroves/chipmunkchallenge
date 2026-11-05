import ChipmunkEngine
import Foundation
import UIKit

/// One board in play: loads (or builds) the board, runs the timed simulation, and takes the player's taps.
/// The SpriteKit scene draws from it every frame; SwiftUI shows its published status.
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
    /// Bumped whenever a new board is ready, so the scene rebuilds.
    @Published private(set) var boardVersion = 0

    let catalog: LevelCatalog
    private(set) var level: Level?
    /// The simulation. The scene reads it to draw critters; only this model changes it.
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
        level = nil
        sim = nil

        let catalog = catalog
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
        if lv.slots != lv.def?.slots, let s = lv.def?.slots { lv.setSlots(s) }
        sim = Sim(lv)
        simT = 0
        status = .playing
        tapFeedback.prepare()
        boardVersion += 1
    }

    /// A different board from the same picture.
    func newBoard() { load(boardIndex, attempt: attempt + 1) }

    func next() { load(min(boardIndex + 1, catalog.levelPlay.count - 1)) }

    func previous() { load(max(boardIndex - 1, 0)) }

    // MARK: - Playing

    /// Move the clock forward by `dt` seconds of real time. `observer` hears every critter event.
    func advance(by dt: TimeInterval, observer: SimObserver) {
        guard status == .playing, let lv = level, var m = sim else { return }
        simT += min(dt, 0.1) / SIM.tickSeconds * (fast ? 3 : 1)
        advanceTo(lv, &m, simT, observer)
        #if DEBUG
        // Launch with `-autoplay YES` to watch the board play its own stored solution (for testing).
        if UserDefaults.standard.bool(forKey: "autoplay"), canTap(lv, m.s),
           let l = planFrom(lv, m.s.lp)?.first, legalMoves(lv, m.s).contains(l) {
            ChipmunkEngine.tap(lv, &m.s, l)
        }
        #endif
        if isCleared(m) {
            status = .won
            notify.notificationOccurred(.success)
        } else if isStuck(lv, &m) {
            status = .stuck
            notify.notificationOccurred(.error)
        }
        sim = m
    }

    /// Tap lane l: its front nest moves into a free slot. Returns false when that isn't possible right now.
    @discardableResult
    func tap(lane l: Int) -> Bool {
        guard status == .playing, let lv = level, var m = sim else { return false }
        guard legalMoves(lv, m.s).contains(l) else { return false }
        // The tap happens on the current tick; anything due before it has already happened.
        ChipmunkEngine.tap(lv, &m.s, l)
        sim = m
        tapFeedback.impactOccurred()
        tapFeedback.prepare()
        return true
    }

    var canTapNow: Bool {
        guard let lv = level, let m = sim else { return false }
        return canTap(lv, m.s)
    }
}

/// Carries a built Level out of the background task (Level is a class the builder no longer touches).
private struct LevelBox: @unchecked Sendable {
    let level: Level?
    init(_ level: Level?) { self.level = level }
}
