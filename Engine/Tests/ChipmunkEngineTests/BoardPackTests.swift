import XCTest
@testable import ChipmunkEngine

/// Downloaded board packs: checking files, the append-only ledger, and merging into the catalog without moving any
/// board the player already has.
final class BoardPackTests: XCTestCase {
    let catalog = try! LevelCatalog.bundled()

    // MARK: - Helpers

    static func picture(_ id: String, color: Character = "G") -> LevelCatalog.Picture {
        let row = String(repeating: "W", count: 10) + String(repeating: color, count: 20) + String(repeating: "W", count: 10)
        return .init(id: id, name: id.capitalized, rows: Array(repeating: row, count: 40))
    }

    static func file(_ id: String, boards n: Int = 20, replace: [String: LevelCatalog.Picture]? = nil) -> BoardPacks.File {
        .init(packs: [.init(id: id, name: id.capitalized, levels: (1...n).map { picture("\(id)-\($0)") })], replace: replace)
    }

    static func entry(_ id: String, data: Data = Data(), min: String = "2.1", format: Int = 1) -> BoardPacks.Entry {
        .init(id: id, name: id, file: "files/\(id).json", sha256: BoardPacks.sha256(data), size: data.count, boards: 20,
              format: format, minAppVersion: min)
    }

    /// Everything that decides how board i plays: its picture, challenge, seed, base and pack bonus.
    func fingerprint(_ c: LevelCatalog, _ i: Int) -> String {
        let p = c.levelPlay[i]
        return "\(p.id)|\(p.rows.joined())|\(c.diffKey(forBoard: i))|\(c.seed(forBoard: i))|\(c.seed(forBoard: i, attempt: 3))|"
            + "\(c.base(forBoard: i))|\(LevelCatalog.aim(c.diffKey(forBoard: i), tailor: 1.3))"
    }

    // MARK: - Bundled boards

    /// Board numbers are the player's progress, so the bundled order must never change. If this fails because packs
    /// were added to boards.json: once any pack has been published for download, new boards go out as downloaded packs
    /// only (tools/publish_pack.py); see the note at the top of LevelCatalog.swift.
    func testBundledOrderIsPinned() {
        let order = (catalog.packs + catalog.newPacks).map { "\($0.id):" + $0.levels.map(\.id).joined(separator: ",") }
        XCTAssertEqual(BoardPacks.sha256(Data(order.joined(separator: ";").utf8)),
                       "88aa0e566e9570f49b61137984467585db226de4746efb301929734a0dad8359")
        XCTAssertEqual(catalog.levelPlay.count, 1075)
    }

    // MARK: - Merging

    func testDownloadedPacksGoOnTheEndAndMoveNothing() {
        let before = catalog
        let n = before.levelPlay.count
        let (after, taken) = before.adding([Self.file("dl1"), Self.file("dl2", boards: 17)])
        XCTAssertEqual(taken, 2)
        XCTAssertEqual(after.levelPlay.count, n + 37)
        XCTAssertEqual(after.allPacks.suffix(2).map(\.id), ["dl1", "dl2"])
        XCTAssertEqual(after.levelPlay[n].id, "dl1-1")
        XCTAssertEqual(after.levelPlay[n + 20].id, "dl2-1")
        for i in Array(0..<25) + Array(stride(from: 25, to: n, by: 37)) + [n - 1] {
            XCTAssertEqual(fingerprint(after, i), fingerprint(before, i), "board \(i + 1)")
        }
        // Coin Mining and the daily puzzle's pool hang off the original boards only.
        XCTAssertEqual(after.paradiseFrom, before.paradiseFrom)
        XCTAssertEqual(after.paradiseRound(33).seed, before.paradiseRound(33).seed)
        XCTAssertEqual(after.bonus(forPack: "dl2"), 4250)
        // New boards build like any other: their number picks the challenge and seed.
        XCTAssertEqual(after.diffKey(forBoard: n), "lv\(n + 1)")
        XCTAssertEqual(after.seed(forBoard: n), (n + 1) * 1000 + 7)
        XCTAssertNil(after.baked(forBoard: n))
    }

    func testAddingMorePacksLaterKeepsEarlierDownloads() {
        let one = catalog.adding([Self.file("dl1")]).catalog
        let two = one.adding([Self.file("dl2")]).catalog
        let both = catalog.adding([Self.file("dl1"), Self.file("dl2")]).catalog
        XCTAssertEqual(two.levelPlay.map(\.id), both.levelPlay.map(\.id))
        for i in one.levelPlay.indices.suffix(30) {
            XCTAssertEqual(fingerprint(two, i), fingerprint(one, i), "board \(i + 1)")
        }
    }

    func testABundledPackIsNotAddedTwice() {
        let bundledPack = catalog.newPacks[3]
        let f = BoardPacks.File(packs: [bundledPack])
        let (after, taken) = catalog.adding([f, Self.file("dl1")])
        XCTAssertEqual(taken, 2)
        XCTAssertEqual(after.levelPlay.count, catalog.levelPlay.count + 20)
    }

    func testClashingBoardIdsHoldBackThatPackAndEveryOneAfter() {
        let clash = BoardPacks.File(packs: [.init(id: "dl1", name: "Clash", levels: [Self.picture(catalog.levelPlay[300].id)])])
        let (after, taken) = catalog.adding([Self.file("dl0"), clash, Self.file("dl2")])
        XCTAssertEqual(taken, 1)
        XCTAssertEqual(after.allPacks.last?.id, "dl0")
        let dup = catalog.adding([Self.file("dl1"), Self.file("dl1")])
        XCTAssertEqual(dup.taken, 1)
    }

    func testAReplacementKeepsItsSlot() {
        let target = catalog.levelPlay[400].id
        let swap = Self.picture("swapped-400", color: "R")
        let (after, taken) = catalog.adding([Self.file("dl1", replace: [target: swap, "no-such-board": swap])])
        XCTAssertEqual(taken, 1)
        XCTAssertEqual(after.levelPlay.count, catalog.levelPlay.count + 20)
        XCTAssertEqual(after.levelPlay[400], swap)
        XCTAssertEqual(after.seed(forBoard: 400), catalog.seed(forBoard: 400))
        XCTAssertEqual(fingerprint(after, 399), fingerprint(catalog, 399))
        XCTAssertEqual(fingerprint(after, 401), fingerprint(catalog, 401))
        // An already-redrawn original can be redrawn again under its original id.
        let redrawn = catalog.replacements.keys.sorted()[0]
        let i = catalog.packs.flatMap(\.levels).firstIndex { $0.id == redrawn }!
        let again = catalog.adding([Self.file("dl1", replace: [redrawn: swap])]).catalog
        XCTAssertEqual(again.levelPlay[i], swap)
    }

    // MARK: - Files

    func testDecodeChecksTheFile() throws {
        let data = try JSONEncoder().encode(Self.file("dl1"))
        let e = Self.entry("dl1", data: data)
        XCTAssertEqual(try BoardPacks.decode(data, for: e).packs[0].levels.count, 20)
        XCTAssertThrowsError(try BoardPacks.decode(data + Data([32]), for: e))
        var wrongSum = e
        wrongSum.sha256 = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try BoardPacks.decode(data, for: wrongSum)) { XCTAssertEqual($0 as? BoardPacks.Problem, .checksum) }
        let other = try JSONEncoder().encode(Self.file("dl2"))
        XCTAssertThrowsError(try BoardPacks.decode(other, for: Self.entry("dl1", data: other))) {
            XCTAssertEqual($0 as? BoardPacks.Problem, .packID)
        }
        var bad = Self.file("dl1")
        let rows = Self.picture("x").rows
        bad.packs = [.init(id: "dl1", name: "Bad", levels: [.init(id: "x", name: "X", rows: Array(rows.dropLast()))])]
        let badData = try JSONEncoder().encode(bad)
        XCTAssertThrowsError(try BoardPacks.decode(badData, for: Self.entry("dl1", data: badData)))
        var future = Self.file("dl1")
        future.format = 2
        let futureData = try JSONEncoder().encode(future)
        XCTAssertThrowsError(try BoardPacks.decode(futureData, for: Self.entry("dl1", data: futureData)))
    }

    func testRealBoardsAreWellFormed() {
        XCTAssertTrue(catalog.levelPlay.allSatisfy(BoardPacks.wellFormed))
    }

    // MARK: - Manifest and ledger

    func testPendingTakesNewPacksInOrder() {
        let m = BoardPacks.Manifest(packs: ["p1", "p2", "p3"].map { Self.entry($0) })
        XCTAssertEqual(BoardPacks.pending(m, have: [], bundled: [], appVersion: "2.1").map(\.id), ["p1", "p2", "p3"])
        XCTAssertEqual(BoardPacks.pending(m, have: ["p1"], bundled: [], appVersion: "2.1").map(\.id), ["p2", "p3"])
        XCTAssertEqual(BoardPacks.pending(m, have: ["p1", "p2", "p3"], bundled: [], appVersion: "2.1"), [])
        // A later app version that bundles p1 and p2.
        XCTAssertEqual(BoardPacks.pending(m, have: [], bundled: ["p1", "p2"], appVersion: "2.2").map(\.id), ["p3"])
        XCTAssertEqual(BoardPacks.pending(m, have: ["p1"], bundled: ["p1", "p2"], appVersion: "2.2").map(\.id), ["p3"])
    }

    func testAManifestThatRewritesHistoryIsIgnored() {
        let have = ["p1", "p2"]
        let reordered = BoardPacks.Manifest(packs: ["p2", "p1", "p3"].map { Self.entry($0) })
        let removed = BoardPacks.Manifest(packs: ["p1", "p3"].map { Self.entry($0) })
        let inserted = BoardPacks.Manifest(packs: ["p1", "p9", "p2", "p3"].map { Self.entry($0) })
        let shorter = BoardPacks.Manifest(packs: ["p1"].map { Self.entry($0) })
        for m in [reordered, removed, inserted, shorter] {
            XCTAssertEqual(BoardPacks.pending(m, have: have, bundled: [], appVersion: "2.1"), [], "\(m.packs.map(\.id))")
        }
        let dup = BoardPacks.Manifest(packs: ["p1", "p2", "p1"].map { Self.entry($0) })
        XCTAssertEqual(BoardPacks.pending(dup, have: [], bundled: [], appVersion: "2.1").map(\.id), ["p1", "p2"])
    }

    func testAgreedCountsTheLedgerPrefixTheManifestKeeps() {
        let m = BoardPacks.Manifest(packs: ["p1", "p2", "p3"].map { Self.entry($0) })
        XCTAssertEqual(BoardPacks.agreed(m, have: ["p1", "p2"], bundled: []), 2)
        XCTAssertEqual(BoardPacks.agreed(m, have: ["p1", "beta9", "p2"], bundled: []), 1)
        XCTAssertEqual(BoardPacks.agreed(m, have: ["p1", "p2", "p3", "p4"], bundled: []), 3)
        XCTAssertEqual(BoardPacks.agreed(m, have: ["p1", "p2", "p3"], bundled: ["p1"]), 3)
        XCTAssertEqual(BoardPacks.agreed(m, have: [], bundled: []), 0)
    }

    func testAPackTooNewForThisAppHoldsBackTheRest() {
        let m = BoardPacks.Manifest(packs: [Self.entry("p1"), Self.entry("p2", min: "2.3"), Self.entry("p3")])
        XCTAssertEqual(BoardPacks.pending(m, have: [], bundled: [], appVersion: "2.1").map(\.id), ["p1"])
        XCTAssertEqual(BoardPacks.pending(m, have: ["p1"], bundled: [], appVersion: "2.3").map(\.id), ["p2", "p3"])
        let newFormat = BoardPacks.Manifest(packs: [Self.entry("p1", format: 2), Self.entry("p2")])
        XCTAssertEqual(BoardPacks.pending(newFormat, have: [], bundled: [], appVersion: "9.0"), [])
        XCTAssertEqual(BoardPacks.pending(BoardPacks.Manifest(format: 2, packs: [Self.entry("p1")]), have: [], bundled: [],
                                          appVersion: "2.1"), [])
    }

    func testVersionCompare() {
        XCTAssertEqual(BoardPacks.compareVersions("2.1", "2.1.0"), .orderedSame)
        XCTAssertEqual(BoardPacks.compareVersions("2.1", "2.10"), .orderedAscending)
        XCTAssertEqual(BoardPacks.compareVersions("3", "2.9.9"), .orderedDescending)
    }
}
