import Foundation
import Security

/// A board waiting for review, as the daily board maker writes it to queue.json.
struct Board: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let rows: [String]
    let judge: Int?
    let reason: String?
    let batch: String?
}

/// Brian's answer for one board. The app writes it as decisions/<id>.json in the queue repo; the Mac's publish job
/// adds approved boards to the game and clears both out of the queue.
struct Decision: Codable, Equatable {
    let id: String
    let name: String
    let decision: String   // "approve" or "deny"
    let at: String
    var approved: Bool { decision == "approve" }
}

/// The queue repo on GitHub, reached with a fine-grained token that can only read and write that one repo.
struct QueueRepo {
    var repo: String
    var token: String

    enum Failure: LocalizedError {
        case http(Int, String)
        var errorDescription: String? {
            switch self {
            case let .http(code, body):
                switch code {
                case 401: return "GitHub didn't accept the token. Paste a new one in Settings."
                case 403, 404: return "The token can't see \(body). Check the repo name and that the token has Contents read and write on it."
                default: return "GitHub error \(code)"
                }
            }
        }
    }

    private func request(_ path: String, method: String = "GET", raw: Bool = false, body: [String: Any]? = nil)
        async throws -> (Data, Int) {
        var r = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/contents/\(path)")!)
        r.httpMethod = method
        r.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue(raw ? "application/vnd.github.raw+json" : "application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body {
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await URLSession.shared.data(for: r)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func ok(_ result: (Data, Int), allow: Set<Int> = []) throws -> Data {
        let (data, code) = result
        guard (200..<300).contains(code) || allow.contains(code) else { throw Failure.http(code, repo) }
        return data
    }

    /// Boards in queue.json.
    func queue() async throws -> [Board] {
        let data = try ok(try await request("queue.json", raw: true))
        return try JSONDecoder().decode([Board].self, from: data)
    }

    /// Decision files already in the repo, by board id, with their blob sha (needed to change or delete one).
    func decisions() async throws -> [String: String] {
        struct Item: Decodable { let name: String; let sha: String }
        let (data, code) = try await request("decisions")
        if code == 404 { return [:] }
        let items = try JSONDecoder().decode([Item].self, from: try ok((data, code)))
        var out: [String: String] = [:]
        for i in items where i.name.hasSuffix(".json") { out[String(i.name.dropLast(5))] = i.sha }
        return out
    }

    private func path(_ id: String) -> String {
        "decisions/" + (id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id) + ".json"
    }

    /// Write (or overwrite) a decision.
    func send(_ d: Decision) async throws {
        let content = try JSONEncoder().encode(d).base64EncodedString()
        var body: [String: Any] = ["message": "\(d.approved ? "Approve" : "Deny") \(d.name)", "content": content]
        if let sha = try await sha(d.id) { body["sha"] = sha }
        _ = try ok(try await request(path(d.id), method: "PUT", body: body))
    }

    /// Take a decision back (undo), if the Mac hasn't applied it yet.
    func remove(_ id: String) async throws {
        guard let sha = try await sha(id) else { return }
        _ = try ok(try await request(path(id), method: "DELETE", body: ["message": "Undo \(id)", "sha": sha]),
                   allow: [404])
    }

    private func sha(_ id: String) async throws -> String? {
        struct Item: Decodable { let sha: String }
        let (data, code) = try await request(path(id))
        if code == 404 { return nil }
        return try JSONDecoder().decode(Item.self, from: try ok((data, code))).sha
    }
}

/// The token lives in the Keychain, this device only.
enum Keychain {
    private static let service = "com.groveseng.boardreviewer.github"

    static var token: String {
        get {
            var out: AnyObject?
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true]
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
            return String(decoding: d, as: UTF8.self)
        }
        set {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
            SecItemDelete(q as CFDictionary)
            guard !newValue.isEmpty else { return }
            var add = q
            add[kSecValueData as String] = Data(newValue.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
