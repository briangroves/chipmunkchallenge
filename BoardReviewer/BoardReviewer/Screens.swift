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

/// The game's 19 colors (Engine/Sources/ChipmunkEngine/Level.swift), so boards look as they will in the game.
let PALETTE: [Character: UInt32] = [
    "R": 0xE53935, "O": 0xFB8C00, "Y": 0xFDD835, "G": 0x43A047, "B": 0x1E88E5, "V": 0x8E24AA,
    "P": 0xF48FB1, "N": 0x795548, "W": 0xF5F5F5, "K": 0x263238, "T": 0xD2B48C, "A": 0x9E9E9E,
    "L": 0x9CCC65, "D": 0x1B5E20, "M": 0x8E1B1B, "C": 0x81D4FA, "U": 0x283593, "I": 0xB39DDB,
    "S": 0xD81B60,
    // Retired shades, drawn as the game plays them, for boards queued before 2026-11-13.
    "Q": 0xFB8C00, "J": 0xFB8C00, "H": 0x81D4FA, "E": 0x795548, "X": 0xF5F5F5, "Z": 0xFDD835,
]

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255)
    }
}

/// A board drawn the way the game shows it: shaded blocks in the sandy tray (BlockArt.swift).
struct BoardPicture: View {
    let rows: [String]
    @Environment(\.displayScale) private var scale

    var body: some View {
        let n = CGFloat((rows.first?.count ?? 1) + 2), m = CGFloat(rows.count + 2) + 0.42
        GeometryReader { geo in
            if let img = BoardArt.image(rows, width: geo.size.width, scale: scale) {
                Image(uiImage: img).resizable().interpolation(.none).frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .aspectRatio(n / m, contentMode: .fit)
    }
}

struct ReviewScreen: View {
    @EnvironmentObject var store: ReviewStore
    @State private var drag: CGSize = .zero
    @State private var showSettings = false
    @State private var denying: Board?
    /// Excellent marks for the board on screen ("subject", "background"); cleared when the next board comes up.
    @State private var stars: Set<String> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if !store.configured {
                    setupPrompt
                } else if let board = store.waiting.first {
                    card(board)
                    ExcellentToggles(stars: $stars)
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
            .sheet(item: $denying) { b in
                DenyScreen(board: b, stars: stars) { reasons, note, excellent in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    stars = []
                    withAnimation { store.decide(b, approve: false, reasons: reasons, note: note, excellent: excellent) }
                }
            }
            .refreshable { await store.refresh() }
            .onChange(of: store.waiting.first?.id) { _, _ in stars = [] }
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
                if v.translation.width > 110 {
                    withAnimation(.easeIn(duration: 0.18)) { drag.width = 600 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        decide(b, true)
                    }
                } else if v.translation.width < -110 {
                    withAnimation(.spring) { drag = .zero }
                    denying = b
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
            Button { denying = b } label: {
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
        let excellent = ExcellentToggles.order.filter(stars.contains)
        stars = []
        withAnimation { store.decide(b, approve: approve, excellent: excellent) }
    }

    private var caughtUp: some View {
        ContentUnavailableView {
            Label("All caught up", systemImage: "checkmark.seal")
        } description: {
            Text("The Mac makes a batch of boards each day and sends them every morning at 6. Pull down to check again.")
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
                    Text("The Mac makes a batch of boards each day and its blob judge keeps the best one of each subject; new ones show up here every morning at 6. A few are test boards outside the judge's usual range, so your answers teach it where boards get too fiddly or too easy. Swipe right or tap Approve to add a board to the game. Swipe left or tap Deny to drop it and say what's wrong: the board maker reads that feedback and steers away from it. Before you decide, tap Excellent subject or Excellent backdrop when that part really knocks it out of the park; the board maker aims for more boards like those. Within about 15 minutes the Mac adds approved boards to the game repo.")
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

/// Deny a board and, optionally, say why. The board maker reads these to steer new boards away from what Brian
/// doesn't like.
struct DenyScreen: View {
    let board: Board
    let deny: ([String], String, [String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [String] = []
    @State private var note = ""
    @State private var stars: Set<String>
    @FocusState private var typing: Bool

    init(board: Board, stars: Set<String>, deny: @escaping ([String], String, [String]) -> Void) {
        self.board = board
        self.deny = deny
        _stars = State(initialValue: stars)
    }

    private func send() {
        deny(picked, note, ExcellentToggles.order.filter(stars.contains))
        dismiss()
    }

    static let reasons = [
        "Too easy (big chunks)", "Bland backdrop", "Flat colors, no shading", "Face hard to read",
        "Doesn't look like its name", "Boring subject", "Muddy or messy", "Blends into backdrop",
        "Too fiddly (tiny pieces)",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        BoardPicture(rows: board.rows)
                            .frame(width: 110, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(board.name).font(.title2.bold())
                            Text("What's wrong with it? Optional, but it teaches the board maker.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(Self.reasons, id: \.self) { r in
                            let on = picked.contains(r)
                            Button {
                                if on { picked.removeAll { $0 == r } } else { picked.append(r) }
                            } label: {
                                Text(r).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 34)
                            }
                            .buttonStyle(.bordered)
                            .tint(on ? .red : .secondary)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.red : .clear, lineWidth: 2))
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Anything excellent anyway?").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        ExcellentToggles(stars: $stars)
                    }
                    TextField("In your own words (e.g. \"needs a pond or flowers behind it\")", text: $note,
                              axis: .vertical)
                        .lineLimit(3...6)
                        .focused($typing)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                    Button {
                        send()
                    } label: {
                        Label("Deny", systemImage: "xmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.red)
                    .font(.title3.weight(.semibold))
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Deny board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {  // reachable while the keyboard covers the big button
                    Button("Deny") { send() }
                    .tint(.red)
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Two toggles for what makes a board stand out, beyond merely good enough. Sent with the decision as
/// `excellent: ["subject", "background"]`; the board maker aims for more boards like these.
struct ExcellentToggles: View {
    @Binding var stars: Set<String>
    static let order = ["subject", "background"]

    var body: some View {
        HStack(spacing: 10) {
            toggle("subject", "Excellent subject", .orange)
            toggle("background", "Excellent backdrop", .teal)
        }
    }

    private func toggle(_ key: String, _ title: String, _ color: Color) -> some View {
        let on = stars.contains(key)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            if on { stars.remove(key) } else { stars.insert(key) }
        } label: {
            Label(title, systemImage: on ? "star.fill" : "star")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .tint(on ? color : .secondary)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? color : .clear, lineWidth: 2))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
