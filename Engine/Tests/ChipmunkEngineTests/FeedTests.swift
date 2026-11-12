import XCTest
@testable import ChipmunkEngine

/// The approved-boards feed may only extend the game's level list, never change what players already have.
final class FeedTests: XCTestCase {
    private func board(_ id: String, _ ch: Character = "G") -> [String: Any] {
        ["id": id, "name": id.capitalized, "rows": Array(repeating: String(repeating: ch, count: 40), count: 40)]
    }

    private func feed(_ ids: [String], badColor: Bool = false) -> Data {
        let levels = ids.map { board($0, badColor && $0 == ids.last ? "!" : "G") }
        let packs = stride(from: 0, to: levels.count, by: 2).map { i -> [String: Any] in
            ["id": "fresh\(i / 2 + 1)", "name": "Fresh Boards \(i / 2 + 1)", "levels": Array(levels[i..<min(i + 2, levels.count)])]
        }
        return try! JSONSerialization.data(withJSONObject: ["format": 1, "packs": packs])
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
}
