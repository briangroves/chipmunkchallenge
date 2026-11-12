import CryptoKit
import Foundation

/// Board packs published after the app shipped, downloaded from a manifest (tools/publish_pack.py writes both).
///
/// The manifest lists every pack ever published, in play order. Each pack file has the shape of boards.json
/// (`{"format", "packs": [...], "replace"?}`) and holds one pack. The app keeps a ledger of the packs it has taken, in
/// order, and only ever adds to its end:
/// - a manifest that disagrees with the ledger about the packs it already has (reordered, removed, swapped) is ignored
///   from that point on, so a published board never changes its number;
/// - packs are taken strictly in order: one this app can't read yet (newer `format` or `minAppVersion`) holds back
///   every pack after it, so an app update can't later slot it in before boards the player already has.
/// A picture swap for a published board goes in a later pack file's `replace` (keyed by board id; it keeps its slot).
public enum BoardPacks {
    /// The pack-file format this engine reads.
    public static let format = 1

    public struct Manifest: Codable, Equatable, Sendable {
        public var format: Int
        public var packs: [Entry]

        public init(format: Int = BoardPacks.format, packs: [Entry]) {
            self.format = format
            self.packs = packs
        }
    }

    /// One pack in the manifest.
    public struct Entry: Codable, Equatable, Sendable {
        /// Unique forever (also the pack's id inside its file).
        public var id: String
        public var name: String
        /// Path of the pack file, relative to the manifest.
        public var file: String
        /// SHA-256 of the pack file, lowercase hex.
        public var sha256: String
        public var size: Int
        public var boards: Int
        public var format: Int
        /// The oldest app version (CFBundleShortVersionString) that may play it.
        public var minAppVersion: String

        public init(id: String, name: String, file: String, sha256: String, size: Int, boards: Int,
                    format: Int = BoardPacks.format, minAppVersion: String) {
            self.id = id
            self.name = name
            self.file = file
            self.sha256 = sha256
            self.size = size
            self.boards = boards
            self.format = format
            self.minAppVersion = minAppVersion
        }
    }

    /// A downloaded pack file.
    public struct File: Codable, Sendable {
        public var format: Int
        public var packs: [LevelCatalog.Pack]
        public var replace: [String: LevelCatalog.Picture]?

        public init(format: Int = BoardPacks.format, packs: [LevelCatalog.Pack], replace: [String: LevelCatalog.Picture]? = nil) {
            self.format = format
            self.packs = packs
            self.replace = replace
        }
    }

    public enum Problem: Error, Equatable {
        case checksum, size, format, packID, badBoard(String)
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Check a downloaded file against its manifest entry and decode it: right size and checksum, a format this engine
    /// reads, exactly the pack the entry names, and every picture a well-formed board.
    public static func decode(_ data: Data, for entry: Entry) throws -> File {
        guard data.count == entry.size else { throw Problem.size }
        guard sha256(data) == entry.sha256.lowercased() else { throw Problem.checksum }
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.format <= format else { throw Problem.format }
        guard file.packs.count == 1, file.packs[0].id == entry.id, !file.packs[0].levels.isEmpty else { throw Problem.packID }
        for pic in file.packs[0].levels + (file.replace.map { Array($0.values) } ?? []) where !wellFormed(pic) {
            throw Problem.badBoard(pic.id)
        }
        return file
    }

    /// 40 rows of 40 palette letters, with an id and a name.
    public static func wellFormed(_ p: LevelCatalog.Picture) -> Bool {
        !p.id.isEmpty && !p.name.isEmpty && p.rows.count == 40
            && p.rows.allSatisfy { $0.count == 40 && $0.allSatisfy { PALETTE[$0] != nil } }
    }

    /// Can this app read the pack?
    public static func readable(_ e: Entry, appVersion: String) -> Bool {
        e.format <= format && compareVersions(e.minAppVersion, appVersion) != .orderedDescending
    }

    /// Manifest packs to download next, in order. `have` is the ledger (pack ids taken so far, in order) and `bundled`
    /// the pack ids already inside the app (a later app version may ship published packs in its bundle). Empty if
    /// the manifest disagrees with the ledger about anything already taken.
    public static func pending(_ manifest: Manifest, have: [String], bundled: Set<String>, appVersion: String) -> [Entry] {
        guard manifest.format <= format else { return [] }
        let remote = manifest.packs.filter { !bundled.contains($0.id) }
        let mine = have.filter { !bundled.contains($0) }
        guard remote.count >= mine.count, zip(remote, mine).allSatisfy({ $0.id == $1 }) else { return [] }
        var out: [Entry] = []
        var seen = Set(have).union(bundled)
        for e in remote.dropFirst(mine.count) {
            guard readable(e, appVersion: appVersion), seen.insert(e.id).inserted else { break }
            out.append(e)
        }
        return out
    }

    /// How many of the ledger's packs (from the start) the manifest still lists in the same order. Below `have.count`
    /// the manifest has rewritten history. Only test builds act on that (dropping the packs after it, e.g. a beta pack
    /// Brian previewed and then pulled); players' builds keep what they have.
    public static func agreed(_ manifest: Manifest, have: [String], bundled: Set<String>) -> Int {
        var remote = manifest.packs.lazy.map(\.id).filter { !bundled.contains($0) }.makeIterator()
        for (k, id) in have.enumerated() where !bundled.contains(id) {
            guard remote.next() == id else { return k }
        }
        return have.count
    }

    /// Dotted version compare ("2.1" < "2.10" < "3").
    public static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p < q ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
