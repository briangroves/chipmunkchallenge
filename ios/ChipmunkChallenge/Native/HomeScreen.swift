import ChipmunkEngine
import SwiftUI

/// The app's root: the home screen or the play screen, with the settings sheet over either.
struct RootView: View {
    @StateObject private var model = GameModel()

    var body: some View {
        ZStack {
            switch model.screen {
            case .home: HomeScreen(model: model).transition(.opacity)
            case .play: PlayScreen(model: model).transition(.opacity)
            }
            if model.settingsOpen {
                SettingsSheet(model: model).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.settingsOpen)
    }
}

// MARK: - Home (.menu)

/// The web page's home screen: the title, hearts and coins, the settings gear, the Level Play and Coin Mining cards
/// side by side, and the Daily Challenge under them. (The gnome's visit and the daily gift aren't built yet.)
struct HomeScreen: View {
    @ObservedObject var model: GameModel

    var body: some View {
        GeometryReader { geo in
            let island = geo.safeAreaInsets.top >= 55
            let w = min(geo.size.width, 560)
            ZStack(alignment: .top) {
                if island {
                    StatusRow(model: model, island: 126, screenWidth: geo.size.width,
                              corner: displayCornerRadius(geo.size.width + geo.safeAreaInsets.leading
                                                          + geo.safeAreaInsets.trailing))
                        .offset(y: 14.5 - geo.safeAreaInsets.top)
                }
                VStack(spacing: 14) {
                    if !island {
                        StatusRow(model: model)
                    }
                    HStack {
                        Text("Chipmunk Challenge")
                            .font(Theme.display(30))
                            .foregroundStyle(model.table.isDark ? .white : Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 8)
                        HUDButton(icon: Icons.gear, size: 15) { model.settingsOpen = true }
                    }
                    HStack(alignment: .top, spacing: 10) {
                        LevelCard(model: model)
                        MiningCard(model: model)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                    DailyCard(model: model)
                    Spacer(minLength: 0)
                }
                .padding(EdgeInsets(top: island ? 8 : 10, leading: 16, bottom: 12, trailing: 16))
                .frame(width: w)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(TableBackground(table: model.table).ignoresSafeArea())
    }
}

/// `.modecard`: a label, the picture, a big line, a small line, and a Play button, filling its half of the row.
private struct ModeCard<Fill: ShapeStyle>: View {
    let label: String
    let rows: [String]
    let big: String
    let sub: AnyView
    let play: String
    let playColor: Color
    let fill: Fill
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .circular)
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label.uppercased())
                    .font(Theme.body(11, 800))
                    .tracking(11 * 0.08)
                    .foregroundStyle(Color(hex: 0x6B7863))
                PictureThumb(rows: rows)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .circular))
                    .padding(.vertical, 2)
                Text(big)
                    .font(Theme.display(24))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                sub
                    .font(Theme.body(12.5, 700))
                    .foregroundStyle(Color(hex: 0x4A5841))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(play)
                    .font(Theme.body(16, 800))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(playColor, in: RoundedRectangle(cornerRadius: 12, style: .circular))
                    .padding(.top, 4)
            }
            .padding(EdgeInsets(top: 12, leading: 8, bottom: 10, trailing: 8))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(Theme.gold, lineWidth: 3))
            .background(shape.fill(.black.opacity(0.08)).offset(y: 2))
        }
        .buttonStyle(Pressable())
    }
}

/// Level Play: the next level (or the one in progress).
private struct LevelCard: View {
    @ObservedObject var model: GameModel

    var body: some View {
        let i = model.homeIndex
        let picture = model.catalog.levelPlay[i]
        let resumes = model.mode == .level && model.status == .playing && model.level != nil
        ModeCard(label: "Level Play", rows: picture.rows, big: "Level \(i + 1)", sub: AnyView(Text(picture.name)),
                 play: resumes ? "Continue" : "Play", playColor: Theme.darkInk, fill: Color.white) {
            withAnimation(.easeOut(duration: 0.2)) { model.playLevel() }
        }
    }
}

/// Coin Mining: the next board, worth 100 coins. (The web version adds a tool; tools aren't built yet.)
private struct MiningCard: View {
    @ObservedObject var model: GameModel

    var body: some View {
        let b = model.miningBoard
        let resumes = model.mode == .mining && model.status == .playing && model.level != nil
        ModeCard(label: "Coin Mining", rows: b.base.rows, big: "Board \(model.paraRound + 1)",
                 sub: AnyView(HStack(spacing: 3) { CoinIcon().frame(width: 12, height: 12); Text("100") }),
                 play: resumes ? "Continue" : "Play", playColor: Color(hex: 0x6B3A1D),
                 fill: LinearGradient(stops: [.init(color: Color(hex: 0xFFF3C4), location: 0),
                                              .init(color: Color(hex: 0xFFD56B), location: 0.6),
                                              .init(color: Color(hex: 0xE8A93A), location: 1)],
                                      startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1))) {
            withAnimation(.easeOut(duration: 0.2)) { model.playMining() }
        }
    }
}

/// `.dailycard`: today's puzzle (its picture in grey), the streak, and Play, or a check once it's done.
private struct DailyCard: View {
    @ObservedObject var model: GameModel

    var body: some View {
        let d = model.dailyBoard
        let done = model.dailyDone
        let streak = model.streakNow
        let resumes = model.mode == .daily && model.status == .playing && model.level != nil
        let shape = RoundedRectangle(cornerRadius: 18, style: .circular)
        Button { withAnimation(.easeOut(duration: 0.2)) { model.playDaily() } } label: {
            HStack(spacing: 10) {
                PictureThumb(rows: model.catalog.levelPlay[d.picture].rows, grey: true)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .circular))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Challenge")
                        .font(Theme.display(19))
                        .foregroundStyle(Theme.ink)
                    Text("Current Streak \(streak) \(streak == 1 ? "day" : "days") 🔥")
                        .font(Theme.body(15, 900))
                        .foregroundStyle(Color(hex: 0xC2410C))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                if done {
                    Text("✓")
                        .font(.system(size: 26, weight: .black))
                        .foregroundStyle(Color(hex: 0x2E7D32))
                        .padding(.horizontal, 6)
                } else {
                    Text(resumes ? "Continue" : "Play")
                        .font(Theme.body(15, 800))
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(Theme.darkInk, in: RoundedRectangle(cornerRadius: 12, style: .circular))
                }
            }
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            .background(shape.fill(LinearGradient(stops: [.init(color: Color(hex: 0xE6F0FF), location: 0),
                                                          .init(color: Color(hex: 0xB9D3FF), location: 0.7),
                                                          .init(color: Color(hex: 0x8FB6F5), location: 1)],
                                                  startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1))))
            .overlay(shape.strokeBorder(Color(hex: 0x5B8FE0), lineWidth: 3))
            .background(shape.fill(.black.opacity(0.08)).offset(y: 2))
            .opacity(done ? 0.8 : 1)
        }
        .buttonStyle(Pressable())
        .disabled(done)
        .accessibilityLabel("Daily Challenge. Current streak \(streak) \(streak == 1 ? "day" : "days")\(done ? ". Done for today" : "")")
    }
}

/// A level's picture, one square per character, like the page's `thumb()` (pixelated, blanks left clear). `grey`
/// draws it washed out in grey, as the daily card does.
struct PictureThumb: View {
    let rows: [String]
    var grey = false

    var body: some View {
        Canvas { g, size in
            let grid = rows.map(Array.init)
            let h = grid.count, w = grid.first?.count ?? 1
            let sx = size.width / CGFloat(w), sy = size.height / CGFloat(h)
            for (r, row) in grid.enumerated() {
                for (k, ch) in row.enumerated() where ch != "." {
                    guard let hex = PALETTE[ch] else { continue }
                    let color: Color
                    if grey {
                        let y = (0.3 * Double(hex >> 16) + 0.59 * Double((hex >> 8) & 255) + 0.11 * Double(hex & 255)) * 0.35 + 150
                        let v = y.rounded() / 255
                        color = Color(red: v, green: min(1, v + 4 / 255), blue: v - 2 / 255)
                    } else {
                        color = Color(hex: hex)
                    }
                    // Overlap by a hair so no seams show between squares.
                    g.fill(Path(CGRect(x: CGFloat(k) * sx, y: CGFloat(r) * sy, width: sx + 0.5, height: sy + 0.5)),
                           with: .color(color))
                }
            }
        }
    }
}

// MARK: - Settings (.settings)

/// The settings card: background, haptics, auto-finish, queueing and the two speeds. (Critters and colorblind
/// mode aren't built yet.)
struct SettingsSheet: View {
    @ObservedObject var model: GameModel

    var body: some View {
        ZStack {
            Color(red: 20 / 255, green: 30 / 255, blue: 15 / 255, opacity: 0.5)
                .ignoresSafeArea()
                .onTapGesture { model.settingsOpen = false }
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Background").font(Theme.body(14, 800)).foregroundStyle(Color(hex: 0x4A5841))
                    HStack(spacing: 6) {
                        ForEach(Table.allCases) { t in
                            TableSwatch(table: t, on: model.table == t) { model.table = t }
                        }
                    }
                }
                SetToggle(title: "Haptics", detail: "A light tap when a nest loads, and a buzz when a board ends.",
                          on: $model.hapticsOn)
                SetToggle(title: "Auto-finish last column",
                          detail: "When only one column is left, its nests load by themselves at fast-forward speed.",
                          on: $model.autoAdvance)
                SetToggle(title: "Queue nests",
                          detail: "When every slot is full, tapping a nest lines it up to load next.",
                          on: $model.queueOn)
                SetSlider(title: "Normal speed", value: $model.speedNormal, range: 0.5...1.5, step: 0.1)
                SetSlider(title: "Fast-forward speed", value: $model.speedFast, range: 1.5...4, step: 0.25)
                Button { model.settingsOpen = false } label: { Text("Done").bigLabel(alt: false) }
                    .buttonStyle(Pressable())
                    .frame(maxWidth: .infinity)
            }
            .padding(18)
            .frame(maxWidth: 360, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .circular).fill(.white)
                .shadow(color: .black.opacity(0.3), radius: 15, y: 10))
            .padding(16)
        }
    }
}

/// `.setrow` with a `.tog` button: a title, a line of explanation, and On/Off.
private struct SetToggle: View {
    let title: String
    let detail: String
    @Binding var on: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.body(14, 800))
                Text(detail)
                    .font(Theme.body(11.5, 500))
                    .foregroundStyle(Color(hex: 0x5A6851))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            Button { on.toggle() } label: {
                Text(on ? "On" : "Off")
                    .font(Theme.body(14, 800))
                    .foregroundStyle(on ? .white : Theme.ink)
                    .frame(minWidth: 52, minHeight: 36)
                    .background(on ? Theme.darkInk : Theme.button, in: RoundedRectangle(cornerRadius: 12, style: .circular))
            }
            .buttonStyle(Pressable())
        }
    }
}

/// `.setslider`: a title with the value on the right, and a slider under it.
private struct SetSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(Theme.body(14, 700))
                Spacer()
                Text(Self.format(value)).font(Theme.body(14, 800))
            }
            .foregroundStyle(Theme.ink)
            Slider(value: $value, in: range, step: step)
                .tint(Theme.darkInk)
        }
    }

    /// The page's fmtX: 1×, 1.5×, 2.25×.
    static func format(_ v: Double) -> String {
        var s = String(format: "%.2f", (v * 100).rounded() / 100)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s + "×"
    }
}
