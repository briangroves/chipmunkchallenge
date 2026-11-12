import ChipmunkEngine
import Foundation

/// New boards approved in the Board Review app, downloaded from the public feed (tools/daily/publish.py writes it).
/// The game checks once a day and right away when the player runs out of levels. The last good copy is kept on the
/// phone, so downloaded boards work offline and survive restarts.
enum BoardFeed {
    static var url: URL {
        #if DEBUG
        // `-boardFeedURL http://localhost:8765/approved.json` tests against a local feed.
        if let s = UserDefaults.standard.string(forKey: "boardFeedURL"), let u = URL(string: s) { return u }
        #endif
        return URL(string: "https://briangroves.github.io/chipmunkchallenge/boards/approved.json")!
    }
    static let checkEvery: TimeInterval = 24 * 3600
    /// Asking again when out of levels is limited to this, so a player stuck on the last board doesn't spam the feed.
    static let retryEvery: TimeInterval = 10 * 60
    private static let lastCheckKey = "native.feedCheckedAt"

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("approved-boards.json")
    }

    /// The copy saved by the last download, if any.
    static var cached: Data? { try? Data(contentsOf: cacheURL) }

    static func save(_ data: Data) { try? data.write(to: cacheURL, options: .atomic) }

    /// Whether it's time to check: a day since the last check, or (when the player is out of levels) ten minutes.
    static func due(urgent: Bool) -> Bool {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        return Date().timeIntervalSince1970 - last >= (urgent ? retryEvery : checkEvery)
    }

    /// The feed as published now, or nil (offline, server trouble). Counts as a check only when it arrives.
    static func download() async -> Data? {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        return data
    }
}
