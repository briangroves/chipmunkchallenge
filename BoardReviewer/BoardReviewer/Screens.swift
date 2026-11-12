import SwiftUI

@main
struct BoardReviewerApp: App {
    @StateObject private var store = ReviewStore()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ReviewScreen()
                .environmentObject(store)
                .task {
                    await Badge.requestPermission()
                    await store.refresh()
                }
                .onChange(of: phase) { _, p in
                    if p == .active { Task { await store.refresh() } }
                    if p == .background { Badge.schedule() }
                }
        }
        .backgroundTask(.appRefresh(Badge.refreshID)) { await Badge.check() }
    }
}

/// The game's 25 colors (Engine/Sources/ChipmunkEngine/Level.swift), so boards look as they will in the game.
let PALETTE: [Character: UInt32] = [
    "R": 0xE53935, "O": 0xFB8C00, "Y": 0xFDD835, "G": 0x43A047, "B": 0x1E88E5, "V": 0x8E24AA,
    "P": 0xF48FB1, "N": 0x795548, "W": 0xF5F5F5, "K": 0x263238, "T": 0xD2B48C, "A": 0x9E9E9E,
    "L": 0x9CCC65, "D": 0x1B5E20, "M": 0x8E1B1B, "C": 0x81D4FA, "U": 0x283593, "I": 0xB39DDB,
    "Q": 0xE65100, "J": 0xFFB74D, "H": 0xB3E5FC, "E": 0x4E342E, "S": 0xD81B60, "Z": 0xFFF59D, "X": 0xD7CCC8,
]

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255)
    }
}

/// A board drawn block by block.
struct BoardPicture: View {
    let rows: [String]

    var body: some View {
        let grid = rows.map(Array.init)
        let n = CGFloat(max(grid.first?.count ?? 1, 1)), m = CGFloat(max(grid.count, 1))
        Canvas { ctx, size in
            let s = min(size.width / n, size.height / m)
            for (r, row) in grid.enumerated() {
                for (c, ch) in row.enumerated() {
                    let rect = CGRect(x: CGFloat(c) * s, y: CGFloat(r) * s, width: s + 0.5, height: s + 0.5)
                    ctx.fill(Path(rect), with: .color(Color(hex: PALETTE[ch] ?? 0xFF00FF)))
                }
            }
        }
        .aspectRatio(n / m, contentMode: .fit)
    }
}

struct ReviewScreen: View {
    @EnvironmentObject var store: ReviewStore
    @State private var drag: CGSize = .zero
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if !store.configured {
                    setupPrompt
                } else if let board = store.waiting.first {
                    card(board)
                    buttons(board)
                } else {
                    caughtUp
                }
                footer
            }
            .padding()
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(store.waiting.isEmpty ? "Board Review" : "\(store.waiting.count) to review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { store.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .disabled(!store.canUndo)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { Task { await store.refresh() } } label: {
                        if store.loading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsScreen().environmentObject(store) }
            .refreshable { await store.refresh() }
        }
    }

    private func card(_ b: Board) -> some View {
        let lean = drag.width
        return VStack(spacing: 12) {
            BoardPicture(rows: b.rows)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: lean > 0 ? .topLeading : .topTrailing) {
                    if abs(lean) > 30 {
                        stamp(lean > 0 ? "APPROVE" : "DENY", lean > 0 ? .green : .red)
                            .opacity(min(1, Double(abs(lean) - 30) / 70))
                    }
                }
            Text(b.name).font(.largeTitle.bold())
            if let j = b.judge {
                HStack(spacing: 2) {
                    Text("Judge").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: i <= j ? "star.fill" : "star").font(.caption)
                            .foregroundStyle(i <= j ? .orange : .secondary)
                    }
                }
            }
            if let r = b.reason {
                Text(r).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .offset(x: drag.width, y: drag.height * 0.2)
        .rotationEffect(.degrees(Double(drag.width) / 25))
        .gesture(DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { v in
                if abs(v.translation.width) > 110 {
                    let approve = v.translation.width > 0
                    withAnimation(.easeIn(duration: 0.18)) { drag.width = approve ? 600 : -600 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        decide(b, approve)
                    }
                } else {
                    withAnimation(.spring) { drag = .zero }
                }
            })
        .id(b.id)
        .transition(.opacity)
    }

    private func stamp(_ text: String, _ color: Color) -> some View {
        Text(text).font(.title.weight(.heavy)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 4))
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.8)))
            .rotationEffect(.degrees(text == "DENY" ? 12 : -12))
            .padding(14)
    }

    private func buttons(_ b: Board) -> some View {
        HStack(spacing: 18) {
            Button { decide(b, false) } label: {
                Label("Deny", systemImage: "xmark").frame(maxWidth: .infinity)
            }
            .tint(.red)
            Button { decide(b, true) } label: {
                Label("Approve", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .tint(.green)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .font(.title3.weight(.semibold))
    }

    private func decide(_ b: Board, _ approve: Bool) {
        UIImpactFeedbackGenerator(style: approve ? .medium : .light).impactOccurred()
        drag = .zero
        withAnimation { store.decide(b, approve: approve) }
    }

    private var caughtUp: some View {
        ContentUnavailableView {
            Label("All caught up", systemImage: "checkmark.seal")
        } description: {
            Text("The Mac makes a new batch every night. Pull down to check again.")
        }
        .frame(maxHeight: .infinity)
    }

    private var setupPrompt: some View {
        ContentUnavailableView {
            Label("Connect to the queue", systemImage: "key")
        } description: {
            Text("Add a GitHub token for the board queue repo in Settings.")
        } actions: {
            Button("Open Settings") { showSettings = true }.buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if store.session.approved + store.session.denied > 0 {
                Text("This session: \(store.session.approved) approved, \(store.session.denied) denied")
            }
            if !store.outbox.isEmpty {
                Text("\(store.outbox.count) decision\(store.outbox.count == 1 ? "" : "s") waiting to send")
                    .foregroundStyle(.orange)
            }
            if let m = store.message { Text(m).foregroundStyle(.red).multilineTextAlignment(.center) }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

struct SettingsScreen: View {
    @EnvironmentObject var store: ReviewStore
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var result: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("owner/repo", text: $store.repo)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Queue repo") }
                Section {
                    SecureField(store.token.isEmpty ? "Paste token" : "Saved. Paste to replace", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Test connection") {
                        if !token.isEmpty { store.token = token.trimmingCharacters(in: .whitespacesAndNewlines) }
                        Task { result = await store.test() }
                    }
                    if let result { Text(result).font(.footnote) }
                } header: { Text("GitHub token") } footer: {
                    Text("A fine-grained token with access to only the queue repo and \"Contents: Read and write\". It's kept in this phone's Keychain.")
                }
                Section {
                    Text("Every night the Mac generates new boards and the judge keeps the best. They show up here. Swipe right or tap Approve to add a board to the game; swipe left or tap Deny to drop it. Within about 15 minutes the Mac adds approved boards to the game repo.")
                        .font(.footnote)
                } header: { Text("How it works") }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if !token.isEmpty { store.token = token.trimmingCharacters(in: .whitespacesAndNewlines) }
                        dismiss()
                        Task { await store.refresh() }
                    }
                }
            }
        }
    }
}
