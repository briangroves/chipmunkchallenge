import XCTest
@testable import ChipmunkEngine

/// The packs made from clipart (Resources/boards.json), played after the original 170 boards.
final class NewBoardTests: XCTestCase {
    let catalog = try! LevelCatalog.bundled()

    private struct Raw: Decodable {
        struct Pack: Decodable { let id: String; let levels: [Board] }
        struct Board: Decodable { let id: String; let theme: String; let variant: Int; let source: Source }
        struct Source: Decodable { let license: String?; let foreign_landing_url: String? }
        let packs: [Pack]
    }

    func testNewPacksFollowTheOriginalBoards() {
        XCTAssertFalse(catalog.newPacks.isEmpty)
        XCTAssertEqual(catalog.paradiseFrom, 170, "Coin Mining and the daily puzzle keep their numbering")
        XCTAssertEqual(catalog.levelPlay.count, 170 + catalog.newPacks.reduce(0) { $0 + $1.levels.count })
    }

    func testPicturesAreWellFormed() {
        for p in catalog.newPacks {
            for L in p.levels {
                XCTAssertEqual(L.rows.count, 40, L.id)
                XCTAssertTrue(L.rows.allSatisfy { $0.count == 40 }, L.id)
                XCTAssertTrue(L.rows.joined().allSatisfy { PALETTE[$0] != nil }, "\(L.id) uses a color outside the palette")
            }
        }
    }

    /// No two boards share a background: each has its own theme and variant, and a license on record.
    func testBackgroundsAreNeverReusedAndSourcesAreRecorded() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "boards", withExtension: "json"))
        let raw = try JSONDecoder().decode(Raw.self, from: Data(contentsOf: url))
        var seen = Set<String>()
        for p in raw.packs {
            for b in p.levels {
                XCTAssertTrue(seen.insert("\(b.theme)#\(b.variant)").inserted, "\(b.id) repeats a background")
                XCTAssertEqual(b.source.license, "cc0", b.id)
                XCTAssertNotNil(b.source.foreign_landing_url, b.id)
            }
        }
    }

    /// The difficulty past 170 eases in at the start of each pack and climbs within it.
    func testDifficultyPastTheOriginalRamp() {
        XCTAssertEqual(Difficulty.rampGoal(171), 0.42, accuracy: 0.001)
        XCTAssertLessThan(Difficulty.rampGoal(190), Difficulty.rampGoal(171))
        XCTAssertGreaterThan(Difficulty.rampGoal(191), Difficulty.rampGoal(190), "a new pack starts gentler")
        XCTAssertLessThan(Difficulty.rampGoal(1000), Difficulty.rampGoal(190))
        XCTAssertGreaterThan(Difficulty.rampGoal(1000), 0.1)
    }

    /// A sample of new boards build, and their stored plan clears them.
    func testNewBoardsBuildAndClear() {
        let first = catalog.paradiseFrom
        for i in stride(from: first, to: catalog.levelPlay.count, by: 6) {
            let key = catalog.diffKey(forBoard: i)
            var o = BuildOptions.game
            o.aim = LevelCatalog.aim(key, tailor: 1)
            guard let lv = generateLevel(base: catalog.base(forBoard: i), seed: catalog.seed(forBoard: i), diffKey: key,
                                         options: o) else {
                XCTFail("board \(i + 1) didn't build")
                continue
            }
            var m = Sim(lv)
            m.pickupPause = 25
            settleTimed(lv, &m)
            for l in lv.plan! {
                if m.s.won || !canTap(lv, m.s) { break }
                tap(lv, &m.s, l)
                settleTimed(lv, &m)
            }
            XCTAssertTrue(m.s.won, "board \(i + 1)")
        }
    }
}
