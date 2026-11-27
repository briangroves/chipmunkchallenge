import Foundation
import XCTest
@testable import ChipmunkEngine

/// Prints how the build meter tracks real time on a spread of game boards (run by hand when tuning BuildPhase).
final class BuildMeterTimingTests: XCTestCase {
    func testMeterTracksTime() throws {
        guard ProcessInfo.processInfo.environment["METER_TIMING"] != nil else { throw XCTSkip("set METER_TIMING=1") }
        let c = try LevelCatalog.bundled()
        var worst = 0.0
        // fraction reached at each 10% of the build's real time, averaged
        var sums = [Double](repeating: 0, count: 11), n = 0.0
        for i in stride(from: 3, to: min(c.levelPlay.count, 400), by: 23) {
            for g in [0.6, 0.25] {
                let key = Difficulty.skillKey(g), seed = c.seed(forBoard: i), p = c.levelPlay[i]
                let cut = pocketBase(c.base(forBoard: i), id: p.id, seed: seed, index: i, board: .level(i + 1), claimed: [])
                var o = BuildOptions.game
                o.aim = LevelCatalog.aim(key, tailor: 1)
                let m = BuildMeter()
                o.meter = m
                var samples: [(Double, Double)] = []
                let t0 = Date()
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    _ = generateLevelRetrying(base: cut.base, seed: seed, diffKey: key, options: o)
                    done.signal()
                }
                while done.wait(timeout: .now() + 0.02) == .timedOut {
                    samples.append((Date().timeIntervalSince(t0), m.fraction))
                }
                let total = Date().timeIntervalSince(t0)
                guard total > 0.3 else { continue }
                var line = String(format: "board %3d g%.2f %.2fs:", i, g, total)
                var dev = 0.0
                for q in 0...10 {
                    let t = total * Double(q) / 10
                    let f = q == 10 ? 1 : (samples.last(where: { $0.0 <= t })?.1 ?? 0)
                    sums[q] += f
                    dev = max(dev, abs(f - Double(q) / 10))
                    line += String(format: " %3.0f", f * 100)
                }
                n += 1
                worst = max(worst, dev)
                print(line, String(format: " maxdev %.2f", dev))
            }
        }
        print("mean:", sums.map { String(format: "%3.0f", $0 / n * 100) }.joined(separator: " "), "worst dev", worst)
    }
}
