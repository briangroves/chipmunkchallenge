import Foundation
import SwiftUI

/// What the app shows and does: the boards still waiting, decisions not yet sent (kept across launches, so a swipe
/// offline isn't lost), and the last few decisions for undo.
@MainActor
final class ReviewStore: ObservableObject {
    @Published private(set) var waiting: [Board] = []
    @Published private(set) var outbox: [Decision] = []
    @Published private(set) var loading = false
    @Published var message: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var session = (approved: 0, denied: 0)
    private var undoStack: [(Board, Decision)] = []

    @Published var repo = UserDefaults.standard.string(forKey: "repo") ?? "briangroves/chipmunk-board-queue" {
        didSet { UserDefaults.standard.set(repo, forKey: "repo") }
    }
    @Published var token = Keychain.token { didSet { Keychain.token = token } }

    var configured: Bool { (!token.isEmpty && repo.contains("/")) || demo }
    private let demo = ProcessInfo.processInfo.environment["DEMO_QUEUE"] != nil
    var canUndo: Bool { !undoStack.isEmpty }
    private var client: QueueRepo { QueueRepo(repo: repo, token: token) }

    private static let outboxKey = "outbox"

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.outboxKey),
           let o = try? JSONDecoder().decode([Decision].self, from: d) { outbox = o }
    }

    private func saveOutbox() {
        UserDefaults.standard.set(try? JSONEncoder().encode(outbox), forKey: Self.outboxKey)
    }

    /// Send anything unsent, then load the queue minus boards already decided.
    func refresh() async {
        // Simulator demo: DEMO_QUEUE=<path to a queue.json on the Mac> shows those boards with no GitHub at all.
        if let demo = ProcessInfo.processInfo.environment["DEMO_QUEUE"] {
            if lastSync == nil, let d = FileManager.default.contents(atPath: demo) {
                waiting = (try? JSONDecoder().decode([Board].self, from: d)) ?? []
                lastSync = Date()
            }
            return
        }
        guard configured, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            await flush()
            async let q = client.queue()
            async let d = client.decisions()
            let (queue, decided) = try await (q, d)
            let mine = Set(outbox.map(\.id))
            waiting = queue.filter { decided[$0.id] == nil && !mine.contains($0.id) }
            lastSync = Date()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func decide(_ board: Board, approve: Bool) {
        let d = Decision(id: board.id, name: board.name, decision: approve ? "approve" : "deny",
                         at: ISO8601DateFormatter().string(from: Date()))
        waiting.removeAll { $0.id == board.id }
        undoStack.append((board, d))
        if undoStack.count > 20 { undoStack.removeFirst() }
        if approve { session.approved += 1 } else { session.denied += 1 }
        outbox.append(d)
        saveOutbox()
        Task { await flush() }
    }

    func undo() {
        guard let (board, d) = undoStack.popLast() else { return }
        waiting.insert(board, at: 0)
        if d.approved { session.approved -= 1 } else { session.denied -= 1 }
        if outbox.contains(where: { $0.id == d.id }) {
            outbox.removeAll { $0.id == d.id }
            saveOutbox()
        } else {
            Task {
                do { try await client.remove(d.id) } catch { message = error.localizedDescription }
            }
        }
    }

    private var flushing = false

    func flush() async {
        guard configured, !demo, !flushing else { return }
        flushing = true
        defer { flushing = false }
        while let d = outbox.first {
            do {
                try await client.send(d)
                outbox.removeAll { $0.id == d.id }
                saveOutbox()
            } catch {
                message = "Saved on this phone; will send when online. (\(error.localizedDescription))"
                return
            }
        }
    }

    func test() async -> String {
        do {
            let q = try await client.queue()
            return "Connected. \(q.count) board\(q.count == 1 ? "" : "s") in the queue."
        } catch {
            return error.localizedDescription
        }
    }
}
