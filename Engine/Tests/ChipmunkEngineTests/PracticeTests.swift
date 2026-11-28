import XCTest
@testable import ChipmunkEngine

final class PracticeTests: XCTestCase {
    /// Every practice board's critters match its blocks color for color, and a careful player always wins.
    func testBoardsAreFair() {
        for k in 0..<Practice.count {
            let lv = Practice.level(k)
            var need = [Int](repeating: 0, count: lv.art.counts.count)
            for n in lv.lanes.joined() { need[n.c] += n.n }
            XCTAssertEqual(need, lv.art.counts, "practice \(k + 1): critters don't match blocks")
            XCTAssertNotNil(lv.plan, "practice \(k + 1) has no solution")
            XCTAssertGreaterThanOrEqual(carefulRate(lv, 150, 11, timed: true), 0.9, "practice \(k + 1)")
        }
    }

    /// The first board can't be lost; each later one is a bit less forgiving of thoughtless taps.
    func testRamp() {
        var rates: [Double] = []
        for k in 0..<Practice.count {
            let lv = Practice.level(k)
            let careful = carefulRate(lv, 150, 11, timed: true), sloppy = carefulRate(lv, 200, 13, 0.3, timed: true)
            let random = carefulRate(lv, 200, 17, 1.0, timed: true)
            print(String(format: "PRACTICE %d %@ nests %d careful %.2f sloppy30 %.2f random %.2f", k + 1, Practice.boards[k].name,
                         lv.lanes.joined().count, careful, sloppy, random))
            rates.append(random)
        }
        XCTAssertEqual(rates[0], 1)
        XCTAssertLessThan(rates[2], 0.7)
    }
}
