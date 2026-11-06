import ChipmunkEngine
import SwiftUI

/// The app's root: the home screen or the play screen, with the settings sheet over either.
struct RootView: View {
    @StateObject private var model = GameModel()
    @SwiftUI.State private var splash = true

    var body: some View {
        ZStack {
            switch model.screen {
            case .home: HomeScreen(model: model).transition(.opacity)
            case .play: PlayScreen(model: model).transition(.opacity)
            }
            if model.settingsOpen {
                SettingsSheet(model: model).transition(.opacity)
            }
            if splash {
                SplashScreen { withAnimation(.easeInOut(duration: 0.45)) { splash = false } }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.settingsOpen)
    }
}

// MARK: - Home (.menu)

/// The home screen: the title and settings gear, Level Play as the big featured card, and Coin Mining and the Daily
/// Challenge side by side under it. Hearts and coins sit beside the Dynamic Island. (The gnome's visit and the daily
/// gift aren't built yet.)
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
                        .offset(y: 29.5 - Chip<EmptyView>.height / 2 - geo.safeAreaInsets.top)
                }
                VStack(spacing: 14) {
                    if !island {
                        StatusRow(model: model)
                    }
                    HStack {
                        Text("Chipmunk Challenge")
                            .font(Theme.display(32))
                            .foregroundStyle(model.table.isDark ? .white : Theme.ink)
                            .shadow(color: .black.opacity(model.table.isDark ? 0.25 : 0), radius: 0, y: 2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 8)
                        HUDButton(icon: Icons.gear, size: 19) { model.settingsOpen = true }
                    }
                    LevelHero(model: model)
                        .frame(maxHeight: .infinity)
                    HStack(alignment: .top, spacing: 12) {
                        MiningCard(model: model)
                        DailyCard(model: model)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(EdgeInsets(top: island ? 8 : 10, leading: 16, bottom: 12, trailing: 16))
                .frame(width: w)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(TableBackground(table: model.table).ignoresSafeArea())
    }
}

/// A chunky game button: a colored pill sitting on a darker edge, so it reads as something to press.
struct PlayPill: View {
    let title: String
    let color: Color
    var height: CGFloat = 40
    var font: Font = Theme.display(19)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.32, style: .continuous)
        Text(title)
            .font(font)
            .tracking(0.3)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(shape.fill(color))
            .background(shape.fill(color).brightness(-0.22).offset(y: 4))
            .padding(.bottom, 4)
    }
}

/// A card's soft drop shadow and colored border.
private struct CardChrome<Fill: ShapeStyle>: ViewModifier {
    let fill: Fill
    let border: Color
    var radius: CGFloat = 20

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: 3))
            .background(shape.fill(.black.opacity(0.12)).offset(y: 4))
    }
}

/// Level Play, featured: the next level's picture as large as the space allows, its number and name, and a big Play.
private struct LevelHero: View {
    @ObservedObject var model: GameModel

    var body: some View {
        let i = model.homeIndex
        let picture = model.catalog.levelPlay[i]
        let resumes = model.mode == .level && model.status == .playing && model.level != nil
        let cols = CGFloat(picture.rows.first?.count ?? 1), rows = CGFloat(max(1, picture.rows.count))
        Button { withAnimation(.easeOut(duration: 0.2)) { model.playLevel() } } label: {
            VStack(spacing: 8) {
                Text("LEVEL PLAY")
                    .font(Theme.body(12, 800))
                    .tracking(12 * 0.1)
                    .foregroundStyle(Color(hex: 0x6B7863))
                PictureThumb(rows: picture.rows)
                    .aspectRatio(cols / rows, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0xEDE4CF)))
                    .frame(maxWidth: 300, maxHeight: .infinity)
                    .layoutPriority(-1)
                VStack(spacing: 0) {
                    Text("Level \(i + 1)")
                        .font(Theme.display(34))
                        .foregroundStyle(Theme.ink)
                    Text(picture.name)
                        .font(Theme.body(16, 700))
                        .foregroundStyle(Color(hex: 0x4A5841))
                        .lineLimit(1)
                }
                PlayPill(title: resumes ? "Continue" : "Play", color: Theme.darkInk, height: 54, font: Theme.display(26))
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
            }
            .padding(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(CardChrome(fill: Color.white, border: Theme.gold, radius: 24))
        }
        .buttonStyle(Pressable())
    }
}

/// A smaller card under the featured one: a label, a picture, a big line, a small line, and a Play button.
private struct ModeCard<Fill: ShapeStyle, Thumb: View>: View {
    let label: String
    let big: String
    let sub: AnyView
    let play: String
    let playColor: Color
    let fill: Fill
    let border: Color
    var disabled = false
    @ViewBuilder let thumb: Thumb
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label.uppercased())
                    .font(Theme.body(11, 800))
                    .tracking(11 * 0.08)
                    .foregroundStyle(Color(hex: 0x5E6B57))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                thumb
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.vertical, 2)
                Text(big)
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                sub
                    .font(Theme.body(12.5, 800))
                    .foregroundStyle(Color(hex: 0x4A5841))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                PlayPill(title: play, color: playColor)
                    .padding(.top, 4)
            }
            .padding(EdgeInsets(top: 12, leading: 10, bottom: 10, trailing: 10))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(CardChrome(fill: fill, border: border))
        }
        .buttonStyle(Pressable())
        .disabled(disabled)
    }
}

/// Coin Mining: the next board, worth 100 coins. (The web version adds a tool; tools aren't built yet.)
private struct MiningCard: View {
    @ObservedObject var model: GameModel

    var body: some View {
        let b = model.miningBoard
        let resumes = model.mode == .mining && model.status == .playing && model.level != nil
        ModeCard(label: "Coin Mining", big: "Board \(model.paraRound + 1)",
                 sub: AnyView(HStack(spacing: 4) { CoinIcon().frame(width: 14, height: 14); Text("+100") }),
                 play: resumes ? "Continue" : "Play", playColor: Color(hex: 0x8A4B22),
                 fill: LinearGradient(stops: [.init(color: Color(hex: 0xFFF3C4), location: 0),
                                              .init(color: Color(hex: 0xFFD56B), location: 0.6),
                                              .init(color: Color(hex: 0xE8A93A), location: 1)],
                                      startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1)),
                 border: Color(hex: 0xE0A21B)) {
            PictureThumb(rows: b.base.rows)
        } action: {
            withAnimation(.easeOut(duration: 0.2)) { model.playMining() }
        }
    }
}

/// The Daily Challenge: today's puzzle, kept a mystery in grey until it's solved, the streak, and Play (or Done).
private struct DailyCard: View {
    @ObservedObject var model: GameModel

    var body: some View {
        let d = model.dailyBoard
        let done = model.dailyDone
        let streak = model.streakNow
        let resumes = model.mode == .daily && model.status == .playing && model.level != nil
        ModeCard(label: "Daily Challenge", big: "🔥 \(streak)",
                 sub: AnyView(Text("day streak")),
                 play: done ? "Done ✓" : resumes ? "Continue" : "Play",
                 playColor: done ? Color(hex: 0x2E7D32) : Color(hex: 0x2F5FB3),
                 fill: LinearGradient(stops: [.init(color: Color(hex: 0xEAF2FF), location: 0),
                                              .init(color: Color(hex: 0xB9D3FF), location: 0.7),
                                              .init(color: Color(hex: 0x8FB6F5), location: 1)],
                                      startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1)),
                 border: Color(hex: 0x5B8FE0), disabled: done) {
            PictureThumb(rows: model.catalog.levelPlay[d.picture].rows, grey: !done)
                .overlay {
                    if !done {
                        Text("?")
                            .font(Theme.display(26))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color(hex: 0x2F5FB3)))
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                    }
                }
        } action: {
            withAnimation(.easeOut(duration: 0.2)) { model.playDaily() }
        }
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
