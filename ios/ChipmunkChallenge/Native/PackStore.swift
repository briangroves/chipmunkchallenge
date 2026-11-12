import ChipmunkEngine
import Foundation

/// New board packs published after the app shipped (tools/publish_pack.py puts them on GitHub Pages).
///
/// Kept in Application Support/BoardPacks: `ledger.json` (the manifest entries taken, in play order) and one file per
/// pack. Packs are only ever added to the end of the ledger (see BoardPacks), so a downloaded board never changes its
/// number. Everything here is best effort: no network, a bad file or a slow server just means no new packs this time.
actor PackStore {
    enum Channel: String {
        /// TestFlight and development builds: previews packs before players get them.
        case beta
        /// App Store builds.
        case live
    }

    static let site = URL(string: "https://briangroves.github.io/chipmunkchallenge/packs/")!

    static var channel: Channel {
        #if DEBUG
        return .beta
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? .beta : .live
        #endif
    }

    /// The manifest to read. Test builds can point elsewhere with the `packManifest` default (a launch argument
    /// `-packManifest http://localhost:8000/beta/manifest.json`, or a file URL), e.g. to try a pack locally.
    static var manifestURL: URL {
        if channel == .beta, let s = UserDefaults.standard.string(forKey: "packManifest"), let u = URL(string: s) {
            return u
        }
        return site.appendingPathComponent(channel.rawValue).appendingPathComponent("manifest.json")
    }

    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    private struct Ledger: Codable {
        var packs: [BoardPacks.Entry]
    }

    nonisolated static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("BoardPacks", isDirectory: true)
    }()

    private nonisolated static var ledgerURL: URL { folder.appendingPathComponent("ledger.json") }

    private nonisolated static func fileURL(_ e: BoardPacks.Entry) -> URL {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return folder.appendingPathComponent(e.id.addingPercentEncoding(withAllowedCharacters: safe) ?? e.id)
            .appendingPathExtension("json")
    }

    private nonisolated static func readLedger() -> [BoardPacks.Entry] {
        guard let data = try? Data(contentsOf: ledgerURL) else { return [] }
        return (try? JSONDecoder().decode(Ledger.self, from: data))?.packs ?? []
    }

    private nonisolated static func writeLedger(_ packs: [BoardPacks.Entry]) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(Ledger(packs: packs)).write(to: ledgerURL, options: .atomic)
    }

    /// The packs saved on this phone, in order, each checked against its checksum. A missing or broken file ends the
    /// list there (the ledger is cut back, so the next check downloads it again and the packs after it, in order).
    nonisolated static func saved() -> [BoardPacks.File] {
        let ledger = readLedger()
        var files: [BoardPacks.File] = []
        for e in ledger {
            guard let data = try? Data(contentsOf: fileURL(e)), let f = try? BoardPacks.decode(data, for: e) else {
                try? writeLedger(Array(ledger.prefix(files.count)))
                break
            }
            files.append(f)
        }
        return files
    }

    /// Check the manifest and download any new packs, in order. `bundled` is the app's own catalog. Returns every
    /// saved pack file (in order) if the set changed, or nil if nothing changed.
    func refresh(bundled: LevelCatalog) async -> [BoardPacks.File]? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 120
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let manifestURL = Self.manifestURL
        guard let data = await Self.fetch(manifestURL, session),
              let manifest = try? JSONDecoder().decode(BoardPacks.Manifest.self, from: data) else { return nil }
        var ledger = Self.readLedger()
        var changed = false
        let bundledIDs = bundled.bundledPackIDs
        // A test build drops previewed packs that the manifest no longer lists (a beta pack that was pulled).
        let agreed = BoardPacks.agreed(manifest, have: ledger.map(\.id), bundled: bundledIDs)
        if Self.channel == .beta, agreed < ledger.count {
            for e in ledger.dropFirst(agreed) { try? FileManager.default.removeItem(at: Self.fileURL(e)) }
            ledger.removeLast(ledger.count - agreed)
            try? Self.writeLedger(ledger)
            changed = true
        }
        var files = Self.saved()
        if files.count < ledger.count { ledger = Array(ledger.prefix(files.count)); changed = true }
        var catalog = bundled.adding(files).catalog
        for e in BoardPacks.pending(manifest, have: ledger.map(\.id), bundled: bundledIDs, appVersion: Self.appVersion) {
            guard let url = URL(string: e.file, relativeTo: manifestURL),
                  let data = await Self.fetch(url, session),
                  let file = try? BoardPacks.decode(data, for: e) else { break }
            let (next, taken) = catalog.adding([file])
            guard taken == 1 else { break }
            do {
                try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
                try data.write(to: Self.fileURL(e), options: .atomic)
                try Self.writeLedger(ledger + [e])
            } catch { break }
            ledger.append(e)
            files.append(file)
            catalog = next
            changed = true
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.checkedKey)
        return changed ? files : nil
    }

    static let checkedKey = "native.packsChecked"

    /// At most one check a day when the app comes back to the front (every launch checks).
    static var due: Bool {
        Date().timeIntervalSince1970 - UserDefaults.standard.double(forKey: checkedKey) > 24 * 3600
    }

    private static func fetch(_ url: URL, _ session: URLSession) async -> Data? {
        if url.isFileURL { return try? Data(contentsOf: url) }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
