import ChipmunkEngine
import SwiftUI

/// Board review (test builds only, from Settings): swipe through every Level Play board, see the score Claude's blind
/// check gave its picture, and rate it 1 to 5 stars. Ratings stay on the phone and can be shared as a CSV.
struct BoardReview: View {
    @ObservedObject var model: GameModel
    @SwiftUI.State private var index = 0
    @SwiftUI.State private var ratings: [String: Int] = BoardReview.loadRatings()
    @SwiftUI.State private var started = false

    /// One row per board in play order: its number, picture, pack and blind-check score.
    struct Entry {
        let number: Int
        let picture: LevelCatalog.Picture
        let pack: String
        let check: Check?
        /// A board from the new board maker's pilot (not in the game yet), with the judge's stars and reason.
        var pilot: Pilot? = nil
    }

    struct Pilot: Decodable {
        let id: String
        let name: String
        let rows: [String]
        let judge: Int
        let reason: String
    }

    struct Check: Decodable {
        let s: Int
        let g: String
        let q: String
    }

    static let ratingsKey = "native.boardRatings"

    /// Shown in Settings on TestFlight and development installs, never in the App Store build.
    static var available: Bool { Bundle.main.appStoreReceiptURL?.lastPathComponent != "receipt" }

    private static let checks: [String: Check] = {
        guard let url = Bundle.main.url(forResource: "board-scores", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Check].self, from: data)) ?? [:]
    }()

    /// New boards waiting for a rating, bundled as pilot-boards.json (shown before the game's boards). The same file
    /// decodes as pictures (id, name, rows) and as the judge's notes.
    private static let pilots: [(LevelCatalog.Picture, Pilot)] = {
        guard let url = Bundle.main.url(forResource: "pilot-boards", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let pics = try? JSONDecoder().decode([LevelCatalog.Picture].self, from: data),
              let notes = try? JSONDecoder().decode([Pilot].self, from: data) else { return [] }
        return Array(zip(pics, notes))
    }()

    private static func loadRatings() -> [String: Int] {
        (UserDefaults.standard.dictionary(forKey: ratingsKey) as? [String: Int]) ?? [:]
    }

    private var entries: [Entry] {
        var out: [Entry] = []
        for (i, (pic, p)) in Self.pilots.enumerated() {
            out.append(Entry(number: i + 1, picture: pic, pack: "New board maker", check: nil, pilot: p))
        }
        let firstLevel = out.count
        for pic in model.catalog.levelPlay {
            out.append(Entry(number: out.count - firstLevel + 1, picture: pic, pack: "Level Play",
                             check: Self.checks[pic.id]))
        }
        return out
    }

    var body: some View {
        let all = entries
        VStack(spacing: 10) {
            header(all)
            TabView(selection: $index) {
                ForEach(all.indices, id: \.self) { i in
                    page(all[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            if all.indices.contains(index) {
                stars(all[index])
            }
        }
        .padding(.bottom, 12)
        .background(TableBackground(table: model.table).ignoresSafeArea())
        .onAppear {
            guard !started else { return }
            started = true
            index = all.firstIndex { ratings[$0.picture.id] == nil } ?? 0
        }
    }

    private func header(_ all: [Entry]) -> some View {
        HStack(spacing: 10) {
            HUDButton(icon: Icons.home, size: 19) {
                withAnimation(.easeOut(duration: 0.2)) { model.reviewOpen = false }
            }
            VStack(spacing: 0) {
                Text("Board review").font(Theme.display(22)).foregroundStyle(chrome)
                Text("\(ratings.count) of \(all.count) rated").font(Theme.body(13, 800)).foregroundStyle(chrome.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            Button {
                if let next = nextUnrated(all, after: index) { withAnimation { index = next } }
            } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 17, weight: .bold))
                    .frame(width: HUDButton.diameter, height: HUDButton.diameter)
                    .background(Circle().fill(.white))
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityLabel("Next unrated board")
            ShareLink(item: csv(all), preview: SharePreview("Board ratings")) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .bold))
                    .frame(width: HUDButton.diameter, height: HUDButton.diameter)
                    .background(Circle().fill(.white))
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityLabel("Share ratings")
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var chrome: Color { model.table.isDark ? .white : Theme.ink }

    private func page(_ e: Entry) -> some View {
        let cols = CGFloat(e.picture.rows.first?.count ?? 1), rows = CGFloat(max(1, e.picture.rows.count))
        return VStack(spacing: 10) {
            VStack(spacing: 0) {
                Text(e.pilot == nil ? "Level \(e.number)" : "New board \(e.number) of \(Self.pilots.count)")
                    .font(Theme.display(30)).foregroundStyle(Theme.ink)
                Text("\(e.picture.name) · \(e.pack)").font(Theme.body(15, 700)).foregroundStyle(Color(hex: 0x4A5841))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            PictureThumb(rows: e.picture.rows)
                .aspectRatio(cols / rows, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(-1)
            if let p = e.pilot { judged(p) } else { score(e.check) }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white))
        .padding(.horizontal, 12)
    }

    @ViewBuilder private func score(_ c: Check?) -> some View {
        if let c {
            let color = c.g == "pass" ? Color(hex: 0x2E7D32) : c.g == "weak" ? Color(hex: 0xC27C0E) : Color(hex: 0xC62828)
            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    Text("Claude's image score").font(Theme.body(14, 700)).foregroundStyle(Color(hex: 0x4A5841))
                    Text("\(c.s)").font(Theme.display(26)).foregroundStyle(color)
                    Text(c.g.uppercased()).font(Theme.body(12, 900)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(color))
                }
                Text("Read it as: \(c.q)").font(Theme.body(13, 600)).foregroundStyle(Color(hex: 0x6B7863))
                    .lineLimit(2).multilineTextAlignment(.center)
            }
        } else {
            Text("No image score").font(Theme.body(14, 700)).foregroundStyle(Color(hex: 0x6B7863))
        }
    }

    private func judged(_ p: Pilot) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Text("Judge's guess of your stars").font(Theme.body(14, 700)).foregroundStyle(Color(hex: 0x4A5841))
                Text("\(p.judge)").font(Theme.display(26)).foregroundStyle(Theme.gold)
                Image(systemName: "star.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.gold)
            }
            Text(p.reason).font(Theme.body(12, 600)).foregroundStyle(Color(hex: 0x6B7863))
                .lineLimit(3).multilineTextAlignment(.center)
        }
    }

    /// Five big stars. A tap saves the rating and moves on to the next board; tapping the same star again clears it.
    private func stars(_ e: Entry) -> some View {
        let id = e.picture.id
        let current = ratings[id] ?? 0
        return HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { n in
                Button {
                    rate(id, current == n ? nil : n)
                    if current != n, index + 1 < entries.count {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            withAnimation(.easeOut(duration: 0.25)) { index += 1 }
                        }
                    }
                } label: {
                    Image(systemName: n <= current ? "star.fill" : "star")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(n <= current ? Theme.gold : chrome.opacity(0.6))
                        .shadow(color: .black.opacity(n <= current ? 0.25 : 0), radius: 0, y: 2)
                        .frame(width: 58, height: 58)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("\(n) star\(n == 1 ? "" : "s")")
            }
        }
    }

    private func rate(_ id: String, _ n: Int?) {
        ratings[id] = n
        UserDefaults.standard.set(ratings, forKey: Self.ratingsKey)
        if n != nil, model.hapticsOn { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }

    private func nextUnrated(_ all: [Entry], after i: Int) -> Int? {
        let order = Array(all.indices[(i + 1)...]) + Array(all.indices[...i])
        return order.first { ratings[all[$0].picture.id] == nil }
    }

    /// Every rated board: number, id, name, pack, stars, and the blind check's score, grade and guess.
    private func csv(_ all: [Entry]) -> String {
        func q(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        var lines = ["level,id,name,pack,stars,claude_score,grade,guess"]
        for e in all {
            guard let r = ratings[e.picture.id] else { continue }
            if let p = e.pilot {
                lines.append(["new", p.id, q(p.name), q(e.pack), String(r), String(p.judge), "judge", ""]
                    .joined(separator: ","))
                continue
            }
            lines.append([String(e.number), e.picture.id, q(e.picture.name), q(e.pack), String(r),
                          e.check.map { String($0.s) } ?? "", e.check?.g ?? "", q(e.check?.q ?? "")].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}
