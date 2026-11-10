import Foundation
import XCTest
@testable import ChipmunkEngine

/// Builds every Level Play board the way the game does and checks each can be won under the game's timing.
/// Slow (all 1,000+ boards), so it only runs when asked:
///
///     FULL_CHECK=1 swift test -c release --filter FullBuildCheckTests
///
/// Optional FULL_CHECK_FROM / FULL_CHECK_TO (1-based board numbers) limit the range. Failures are listed in the
/// test output and written to $TMPDIR/full-build-check.txt.
final class FullBuildCheckTests: XCTestCase {
    func testEveryBoardBuildsAndCanBeWon() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["FULL_CHECK"] == "1", "set FULL_CHECK=1 to build every board")
        let catalog = try LevelCatalog.bundled()
        let from = max(1, Int(env["FULL_CHECK_FROM"] ?? "") ?? 1) - 1
        let to = min(catalog.levelPlay.count, Int(env["FULL_CHECK_TO"] ?? "") ?? catalog.levelPlay.count)
        let boards = Array(from..<to)
        let lock = NSLock()
        var problems: [Int: String] = [:]
        var retried: [Int] = []
        DispatchQueue.concurrentPerform(iterations: boards.count) { n in
            let i = boards[n]
            let key = catalog.diffKey(forBoard: i)
            var o = BuildOptions.game
            o.aim = LevelCatalog.aim(key, tailor: 1)
            let base = catalog.base(forBoard: i)
            let seed = catalog.seed(forBoard: i)
            let lv: Level
            var note: String?
            if let b = catalog.baked(forBoard: i) {
                lv = assembleLevel(base: base, diffKey: key, seed: seed, summary: b, aim: o.aim)
            } else if let first = generateLevel(base: base, seed: seed, diffKey: key, options: o) {
                lv = first
            } else if let again = generateLevelRetrying(base: base, seed: seed, diffKey: key, options: o) {
                lv = again
                note = "retried"
            } else {
                lock.lock(); problems[i] = "doesn't build (6 seeds)"; lock.unlock()
                return
            }
            var m = Sim(lv)
            m.pickupPause = 25
            settleTimed(lv, &m)
            for l in lv.plan ?? [] {
                if m.s.won || !canTap(lv, m.s) { break }
                tap(lv, &m.s, l)
                settleTimed(lv, &m)
            }
            if !m.s.won {
                var m0 = Sim(lv)
                m0.pickupPause = 25
                let sol = solve(lv, m0, cap: 20000)
                if sol.path == nil {
                    lock.lock()
                    problems[i] = sol.aborted ? "no win found (search capped)" : "can't be won"
                    lock.unlock()
                }
            }
            if note != nil { lock.lock(); retried.append(i); lock.unlock() }
        }
        let lines = problems.keys.sorted().map { "board \($0 + 1) (\(catalog.levelPlay[$0].id)): \(problems[$0]!)" }
        let report = "checked \(boards.count) boards; \(problems.count) problems; \(retried.count) needed a retry seed\n"
            + lines.joined(separator: "\n") + "\nretried: \(retried.sorted().map { $0 + 1 })\n"
        print(report)
        try? report.write(toFile: NSTemporaryDirectory() + "full-build-check.txt", atomically: true, encoding: .utf8)
        XCTAssertTrue(problems.isEmpty, report)
    }
}
