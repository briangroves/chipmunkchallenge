import XCTest
@testable import ChipmunkEngine

/// The approved-boards feed may only extend the game's level list, never change what players already have.
final class FeedTests: XCTestCase {
    private func board(_ id: String, _ ch: Character = "G") -> [String: Any] {
        ["id": id, "name": id.capitalized, "rows": Array(repeating: String(repeating: ch, count: 40), count: 40)]
    }

    /// The feed as tools/daily/publish.py writes it: one flat list of boards, each added as soon as it's approved.
    private func feed(_ ids: [String], badColor: Bool = false) -> Data {
        let levels = ids.map { board($0, badColor && $0 == ids.last ? "!" : "G") }
        return try! JSONSerialization.data(withJSONObject: ["format": 2, "levels": levels])
    }

    /// A feed written before 2026-11-13, with the boards grouped in packs: read as one list in order.
    private func packedFeed(_ ids: [String]) -> Data {
        let levels = ids.map { board($0) }
        let packs = stride(from: 0, to: levels.count, by: 2).map { i -> [String: Any] in
            ["id": "fresh\(i / 2 + 1)", "name": "Fresh Boards \(i / 2 + 1)", "levels": Array(levels[i..<min(i + 2, levels.count)])]
        }
        return try! JSONSerialization.data(withJSONObject: ["format": 1, "packs": packs])
    }

    func testOneNewBoardArrivesOnItsOwn() throws {
        var c = try LevelCatalog.bundled()
        let start = c.approvedBoards.map(\.id)
        XCTAssertEqual(c.merge(feed: feed(start + ["a"])), 1, "a single approved board is enough")
        XCTAssertEqual(c.levelPlay.last?.id, "a")
    }

    func testOlderPackedFeedStillReads() throws {
        var c = try LevelCatalog.bundled()
        let start = c.approvedBoards.map(\.id)
        XCTAssertEqual(c.merge(feed: packedFeed(start + ["a", "b", "c"])), 3)
        XCTAssertEqual(Array(c.levelPlay.suffix(3).map(\.id)), ["a", "b", "c"])
    }

    func testFeedOnlyExtends() throws {
        var c = try LevelCatalog.bundled()
        let shipped = c.levelPlay.count
        let start = c.approvedBoards.map(\.id)
        XCTAssertEqual(c.merge(feed: feed(start + ["a", "b", "c"])), 3)
        XCTAssertEqual(c.levelPlay.count, shipped + 3)
        XCTAssertEqual(Array(c.levelPlay.suffix(3).map(\.id)), ["a", "b", "c"])
        let before = c.levelPlay.map(\.id)
        // Older, reordered, or broken copies are ignored.
        XCTAssertEqual(c.merge(feed: feed(start + ["a", "b"])), 0)
        XCTAssertEqual(c.merge(feed: feed(start + ["b", "a", "c", "d"])), 0)
        XCTAssertEqual(c.merge(feed: feed(start + ["a", "b", "c", "d"], badColor: true)), 0)
        XCTAssertEqual(c.merge(feed: Data("<html>404</html>".utf8)), 0)
        XCTAssertEqual(c.levelPlay.map(\.id), before)
        // A longer copy that keeps the same start is taken.
        XCTAssertEqual(c.merge(feed: feed(start + ["a", "b", "c", "d"])), 1)
        XCTAssertEqual(c.levelPlay.map(\.id), before + ["d"])
    }

    // MARK: - Boards denied on a second look (boards.json "skip")

    func testFingerprintMatchesSnapshotScript() {
        // tools/daily/snapshot_feed.py fingerprint(["GG", "RB"]) and fingerprint([]).
        XCTAssertEqual(LevelCatalog.fingerprint(["GG", "RB"]), "fdc38ae4fd6feb0b")
        XCTAssertEqual(LevelCatalog.fingerprint([]), "cbf29ce484222325")
    }

    func testSkippedBoardsArePassedOverButKeepTheirPlace() throws {
        let c = try LevelCatalog.bundled()
        let all = c.levelPlay
        for i in c.skippedIndices {
            XCTAssertEqual(c.skipped[all[i].id], LevelCatalog.fingerprint(all[i].rows))
            XCTAssertNotEqual(c.playable(from: i), i)
        }
        // Played levels are numbered 1, 2, 3... with no gaps; seeds still follow the board's own index.
        var expected = 1
        for i in all.indices where !c.isSkipped(i) {
            XCTAssertEqual(c.levelNumber(forBoard: i), expected)
            XCTAssertEqual(c.playable(from: i), i)
            XCTAssertEqual(c.seed(forBoard: i), (i + 1) * 1000 + 7)
            expected += 1
        }
        XCTAssertEqual(expected - 1, all.count - c.skippedIndices.count)
    }

    func testANewBoardInADeniedSlotPlaysAgain() throws {
        var c = try LevelCatalog.bundled()
        guard let i = c.skippedIndices.min() else { throw XCTSkip("this build skips no boards") }
        let id = c.levelPlay[i].id
        // The feed as publish.py writes it after a new board fills the slot: same id and place, new rows.
        let start = c.approvedBoards.map(\.id)
        let levels: [[String: Any]] = (start + ["z"]).map { $0 == id ? board($0, "R") : board($0) }
        // Boards that aren't changed keep their own rows (the helper's are all G), so take the real ones.
        let real = Dictionary(uniqueKeysWithValues: c.approvedBoards.map { ($0.id, $0.rows) })
        let fixed = levels.map { L -> [String: Any] in
            var L = L
            if let id2 = L["id"] as? String, id2 != id, let r = real[id2] { L["rows"] = r }
            return L
        }
        let data = try JSONSerialization.data(withJSONObject: ["format": 2, "levels": fixed])
        let before = c.skippedIndices.count
        XCTAssertEqual(c.merge(feed: data), 1)
        XCTAssertFalse(c.isSkipped(i), "the new board in the slot plays")
        XCTAssertEqual(c.skippedIndices.count, before - 1)
    }
}
