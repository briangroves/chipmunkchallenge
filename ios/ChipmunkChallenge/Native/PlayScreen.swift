import ChipmunkEngine
import SwiftUI

/// The play screen, laid out like the web page's `.game` card: the title bar and buttons, then the wooden stage with
/// the HUD, the board, the holding slots, the lanes of nests and the tool bar. Sizes come from the page's CSS.
struct PlayScreen: View {
    @ObservedObject var model: GameModel

    var body: some View {
        GeometryReader { geo in
            // The wood is the only background, edge to edge. No title bar: the buttons live in the HUD.
            // Everything fits on one screen, no scrolling.
            let w = min(geo.size.width, 560)
            // On Dynamic Island phones the hearts and coins sit in the island's row, either side of it; elsewhere
            // they sit at the top of the stage. The control buttons are always the stage's first row.
            let island = geo.safeAreaInsets.top >= 55
            ZStack(alignment: .top) {
                Stage(model: model, width: w, maxHeight: geo.size.height, showsHUD: !island)
                if model.toolsOpen && model.status == .playing {
                    ToolTray()
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom))
                }
                // Scenes and cards cover the whole screen, edge to edge; the HUD stays on top of the cards.
                ZStack {
                    if model.cardShown {
                        ResultCard(model: model)
                        if !island {
                            StatusRow(model: model)
                                .padding(EdgeInsets(top: 10, leading: 6, bottom: 0, trailing: 6))
                                .frame(width: w)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                    if island && model.scene == nil && model.status != .building {
                        StatusRow(model: model, island: 126, screenWidth: geo.size.width,
                                  corner: displayCornerRadius(geo.size.width + geo.safeAreaInsets.leading
                                                              + geo.safeAreaInsets.trailing))
                            // Centered on the island: it spans 11 to 48 points from the top on current phones.
                            .offset(y: 29.5 - Chip<EmptyView>.height / 2 - geo.safeAreaInsets.top)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    if let run = model.scene {
                        SceneLayer(model: model, run: run).id(run.id)
                    } else if model.status == .building {
                        ProgressView().controlSize(.large).tint(Theme.ink)
                    } else if case .failed = model.status {
                        ResultCard(model: model)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(TableBackground(table: model.table).ignoresSafeArea())
    }
}

/// A small round icon button in the control row (restart, undo, fast, backpack, home, settings).
struct HUDButton: View {
    static let diameter: CGFloat = 36
    let icon: SVGShape
    var size: CGFloat = 20
    var disabled = false
    var on = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon
                .fill(on ? Theme.gold : Theme.ink, style: FillStyle(eoFill: true))
                .frame(width: size, height: size)
                .frame(width: HUDButton.diameter, height: HUDButton.diameter)
                .background(Circle().fill(on ? Theme.darkInk : .white.opacity(0.88))
                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1))
        }
        .buttonStyle(Pressable())
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

// MARK: - Stage (.stage)

private struct Stage: View {
    @ObservedObject var model: GameModel
    let width: CGFloat
    let maxHeight: CGFloat
    var showsHUD = true

    /// Padding, the hearts and coins row (when it isn't beside the island) and the control row.
    private var top: CGFloat { showsHUD ? 10 + Chip<EmptyView>.height + 6 + HUDButton.diameter + 8 : 4 + HUDButton.diameter + 8 }

    /// Height of a slot, the full lane box (three rows plus a fifth of the fourth) and one row of lanes, for slots
    /// and lanes `w` wide.
    private func rows(_ w: CGFloat) -> (slot: CGFloat, lanes: CGFloat, nest: CGFloat) {
        let n = CGFloat(max(1, model.side.slots.count)), cols = CGFloat(max(1, model.side.columns))
        let nest = (w - (cols - 1) * 6) / cols * 0.88
        return ((w - (n - 1) * 6) / n, CGFloat(JSRound(Double(3 * nest + 18 + nest * Lanes.peek))), nest)
    }

    /// Stage height with the board's cells `cs` and slots and lanes `w` wide: the top, the board, the slots, 12,
    /// the lanes and padding 8. The tools aren't in the stage: they slide up over the lanes from the backpack.
    private func stageHeight(_ cs: CGFloat, NH: Int, w: CGFloat, lanes: CGFloat? = nil) -> CGFloat {
        let r = rows(w)
        return top + drop(w) + CGFloat(NH) * cs + r.slot + 12 + (lanes ?? r.lanes) + 8
    }

    /// Extra room above the board: two thirds of a queue nest's width.
    private func drop(_ w: CGFloat) -> CGFloat { (rows(w).nest * 2 / 3).rounded() }

    /// The board's cell size, the slots' and lanes' width, and the lane box's height.
    private func fit() -> (CGFloat, CGFloat, CGFloat) {
        let scale = UIScreen.main.scale
        let NW = model.level?.NW ?? 42, NH = model.level?.NH ?? 49
        var classic = BoardView.cellSize(width: min(width - 20, 520), NW: NW, scale: scale)
        while classic > 4 {
            let r = rows(CGFloat(NW) * classic)
            if 50 + CGFloat(NH) * classic + r.slot + 12 + r.lanes + 12 + 52 + 8 <= maxHeight { break }
            classic -= 1 / scale
        }
        let laneW = CGFloat(NW) * classic
        let r = rows(laneW)
        let minLanes = (r.nest * 1.35 + 12).rounded()
        var cs = BoardView.cellSize(width: min(width - 12, 520), NW: NW, scale: scale)
        // Shrink the board (never below the classic size) until three rows and a good look at the fourth fit.
        while cs > classic, stageHeight(cs, NH: NH, w: laneW) > maxHeight { cs -= 1 / scale }
        let lanesH = max(minLanes, min(r.lanes, maxHeight - stageHeight(cs, NH: NH, w: laneW, lanes: 0)))
        return (cs, laneW, lanesH)
    }

    var body: some View {
        // The slots and nests keep the size they had when the board was sized to fit the whole stage with the HUD
        // above it. The board itself then runs nearly edge to edge; the slots, lanes and tools move down, and the
        // lanes show fewer of the waiting rows. If even a row and a bit no longer fits, the board shrinks.
        let NH = model.level?.NH ?? 49
        let (cs, laneW, lanesH) = fit()
        let boardW = CGFloat(model.level?.NW ?? 42) * cs
        VStack(spacing: 0) {
            if showsHUD {
                StatusRow(model: model)
                    .padding(.bottom, 6)
            }
            ControlRow(model: model)
                .padding(.horizontal, 4)   // 10 points in from the screen's edges
                .padding(.bottom, 8 + drop(laneW))
            BoardCanvas(model: model)
                .frame(width: boardW, height: CGFloat(NH) * cs)
                .onAppear { model.cellSize = cs }
                .onChange(of: cs) { _, v in model.cellSize = v }
            VStack(spacing: 12) {
                Slots(model: model, width: laneW)
                Lanes(model: model, width: laneW, height: lanesH)
            }
            .frame(width: laneW)
        }
        .padding(EdgeInsets(top: showsHUD ? 10 : 4, leading: 6, bottom: 8, trailing: 6))
        .frame(width: width)
    }
}

/// `.t-wood`: planks 44 points wide in two tones, with a thin darker seam at each plank's left edge.
struct WoodBackground: View {
    var body: some View {
        Canvas { g, size in
            var x: CGFloat = 0, k = 0
            while x < size.width {
                g.fill(Path(CGRect(x: x, y: 0, width: 44, height: size.height)),
                       with: .color(Color(hex: k % 2 == 0 ? 0xF0CFA4 : 0xEBC597)))
                g.fill(Path(CGRect(x: x, y: 0, width: 2, height: size.height)),
                       with: .color(Color(red: 150 / 255, green: 92 / 255, blue: 40 / 255, opacity: 0.13)))
                x += 44
                k += 1
            }
        }
    }
}

// MARK: - HUD (.hud)

/// The screen's corner radius in points, by screen width (Apple doesn't publish it; these are the measured values).
func displayCornerRadius(_ width: CGFloat) -> CGFloat {
    switch width {
    case 402, 420, 440: return 62   // iPhone 16 Pro / 17 / 17 Pro, Air, Pro Max
    default: return 55              // iPhone 14 Pro – 16, Plus and Pro Max of those years
    }
}

/// Hearts on the left, coins on the right. Beside a Dynamic Island `island` points wide, each is centered between
/// the island's edge and the center of the screen's corner curve; otherwise they sit at the row's ends.
struct StatusRow: View {
    @ObservedObject var model: GameModel
    var island: CGFloat? = nil
    var screenWidth: CGFloat = 0
    var corner: CGFloat = 0

    var body: some View {
        Group {
            if let island {
                let edge = (screenWidth - island) / 2
                ZStack {
                    hearts.position(x: (corner + edge) / 2, y: Chip<EmptyView>.height / 2)
                    coins.position(x: screenWidth - (corner + edge) / 2, y: Chip<EmptyView>.height / 2)
                }
                .frame(width: screenWidth, height: Chip<EmptyView>.height)
            } else {
                HStack { hearts; Spacer(); coins }
            }
        }
        .font(Theme.body(16, 800))
        .foregroundStyle(Theme.ink)
    }

    private var hearts: some View {
            // The heart chip also holds the (empty) refill timer, whose 4pt gap still takes room.
            Chip(leading: 9, trailing: 12) {
                HStack(spacing: 4) {
                    Icons.heart
                        .fill(Color(hex: 0xE53935))
                        .overlay(Icons.heart.stroke(Color(hex: 0x9C1F1D), lineWidth: 1.4 * 15 / 24))
                        .frame(width: 19, height: 18)
                        .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
                    Text("5")
                }
            }
    }

    private var coins: some View {
            Chip(leading: 5, trailing: 10) {
                HStack(spacing: 4) {
                    CoinIcon().frame(width: 20, height: 20)
                    Text(model.coins.formatted())
                }
            }
    }
}

/// Restart (after a confirmation), undo and fast on the left, then room for the warning icon and the mystery box (not built yet); the backpack
/// (which shows the tools), home and settings on the right.
private struct ControlRow: View {
    @ObservedObject var model: GameModel
    @SwiftUI.State private var confirmRestart = false

    var body: some View {
        HStack(spacing: 4) {
            HUDButton(icon: Icons.restart) { confirmRestart = true }
                .alert("Restart this level?", isPresented: $confirmRestart) {
                    Button("Restart", role: .destructive) { model.restartButton() }
                    Button("Keep playing", role: .cancel) {}
                } message: {
                    Text("You'll start over from the beginning and lose your progress on this level.")
                }
            HUDButton(icon: Icons.undo, disabled: !model.canUndo) { model.undo() }
            HUDButton(icon: Icons.speed, on: model.fast) { model.toggleFast() }
            Color.clear.frame(width: HUDButton.diameter, height: HUDButton.diameter)   // warning icon
            Color.clear.frame(width: HUDButton.diameter, height: HUDButton.diameter)   // mystery box
            Spacer(minLength: 4)
            HUDButton(icon: Icons.backpack, on: model.toolsOpen) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { model.toolsOpen.toggle() }
            }
            HUDButton(icon: Icons.home) { withAnimation(.easeOut(duration: 0.2)) { model.goHome() } }
            HUDButton(icon: Icons.gear, size: 19) { model.settingsOpen = true }
        }
    }
}

/// `.hud .chip`: a white pill 30 points tall.
struct Chip<Content: View>: View {
    static var height: CGFloat { 36 }
    let leading: CGFloat
    let trailing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .frame(height: Chip.height)
            .background(Capsule().fill(.white.opacity(0.88)).shadow(color: .black.opacity(0.12), radius: 1.5, y: 1))
    }
}

/// `.coin`: a gold coin with a raised rim.
struct CoinIcon: View {
    var body: some View {
        Canvas { g, size in
            let r = size.width / 2, c = CGPoint(x: r, y: r)
            let circle = Path(ellipseIn: CGRect(origin: .zero, size: size))
            // radial-gradient(circle at 35% 30%, #fff6c2 0 12%, #ffd23a 38%, #e2a100), farthest-corner
            let fx = size.width * 0.35, fy = size.height * 0.3
            let far = hypot(size.width - fx, size.height - fy)
            g.fill(circle, with: .radialGradient(
                Gradient(stops: [.init(color: Color(hex: 0xFFF6C2), location: 0), .init(color: Color(hex: 0xFFF6C2), location: 0.12),
                                 .init(color: Color(hex: 0xFFD23A), location: 0.38), .init(color: Color(hex: 0xE2A100), location: 1)]),
                center: CGPoint(x: fx, y: fy), startRadius: 0, endRadius: far))
            // Inset rings, bottom layer first: 6.5px brown, 5px pale, 2px dark rim.
            for (w, color) in [(6.5, Color(red: 185 / 255, green: 124 / 255, blue: 0, opacity: 0.55)),
                               (5.0, Color(red: 1, green: 236 / 255, blue: 150 / 255, opacity: 0.55)),
                               (2.0, Color(hex: 0xB97C00))] as [(CGFloat, Color)] {
                var ring = Path(ellipseIn: CGRect(origin: .zero, size: size))
                ring.addEllipse(in: CGRect(x: c.x - (r - w), y: c.y - (r - w), width: 2 * (r - w), height: 2 * (r - w)))
                g.fill(ring, with: .color(color), style: FillStyle(eoFill: true))
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
    }
}

// MARK: - Slots and nests

private struct Slots: View {
    @ObservedObject var model: GameModel
    let width: CGFloat

    var body: some View {
        let n = max(1, model.side.slots.count)
        let size = (width - CGFloat(n - 1) * 6) / CGFloat(n)
        HStack(spacing: 6) {
            ForEach(0..<n, id: \.self) { k in
                let item = k < model.side.slots.count ? model.side.slots[k] : nil
                if let item {
                    NestTile(color: model.hex(item.c), count: item.r, size: size, fontSize: 26, front: false, key: item.key)
                } else if model.side.lockedAt == k {
                    LockedSlot(size: size)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .circular)
                        .fill(.white.opacity(0.92))
                        .background(RoundedRectangle(cornerRadius: 14, style: .circular).fill(.black.opacity(0.12)).offset(y: 3))
                        .frame(width: size, height: size)
                }
            }
        }
        .frame(width: width)
    }
}

/// `.slot.locked`: grey stripes, an inner ring, and a padlock.
private struct LockedSlot: View {
    let size: CGFloat

    var body: some View {
        Canvas { g, sz in
            let shape = RoundedRectangle(cornerRadius: 14, style: .circular).path(in: CGRect(origin: .zero, size: sz))
            g.clip(to: shape)
            // repeating-linear-gradient(135deg, #d9d2c3 0 6px, #cdc5b4 6px 12px)
            g.fill(Path(CGRect(origin: .zero, size: sz)), with: .color(Color(hex: 0xD9D2C3)))
            let step: CGFloat = 12 * sqrt(2)
            var t: CGFloat = -sz.height
            while t < sz.width + sz.height {
                var p = Path()
                p.move(to: CGPoint(x: t + 6 * sqrt(2), y: 0))
                p.addLine(to: CGPoint(x: t + step, y: 0))
                p.addLine(to: CGPoint(x: t + step + sz.height, y: sz.height))
                p.addLine(to: CGPoint(x: t + 6 * sqrt(2) + sz.height, y: sz.height))
                g.fill(p, with: .color(Color(hex: 0xCDC5B4)))
                t += step
            }
            g.stroke(shape, with: .color(Color(hex: 0xA99F8B)), lineWidth: 4)
        }
        .frame(width: size, height: size)
        .overlay(Text("🔒").font(.system(size: 20)))
    }
}

/// `.slot.full` / `.nest`: a block in the nest's color with a dark lower band, a soft highlight, and the critter
/// count in Lilita One with a brown outline. The front nest of a lane gets a white ring.
struct NestTile: View {
    let color: UInt32
    let count: Int
    let size: CGFloat
    let fontSize: CGFloat
    let front: Bool
    let key: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
        ZStack {
            shape.fill(Color(hex: color))
            // inset 0 -8px 0 rgba(0,0,0,.26): a band along the bottom, following the corner curve
            Canvas { g, sz in
                let r = CGRect(origin: .zero, size: sz)
                var band = Path(r)
                band.addPath(shape.path(in: r.offsetBy(dx: 0, dy: -8)))
                g.clip(to: shape.path(in: r))
                g.fill(band, with: .color(.black.opacity(0.26)), style: FillStyle(eoFill: true))
            }
            // inset 0 0 0 1px rgba(0,0,0,.08)
            shape.strokeBorder(.black.opacity(0.08), lineWidth: 1)
            // ::before: left/right 11%, top 9%, bottom 24%, radius 10, white .13 with a 1px light top edge
            RoundedRectangle(cornerRadius: 10, style: .circular)
                .fill(.white.opacity(0.13))
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 10, style: .circular)
                        .fill(.white.opacity(0.22))
                        .mask(alignment: .top) { Rectangle().frame(height: 1) }
                }
                .padding(EdgeInsets(top: size * 0.09, leading: size * 0.11, bottom: size * 0.24, trailing: size * 0.11))
            // margin-top:-8%, plus 0.095em: CSS places Lilita One's line box a little lower than SwiftUI does
            OutlinedNumber(text: "\(count)", size: fontSize)
                .offset(y: -0.08 * size + 0.095 * fontSize)
            if key {
                Text("🔑").font(.system(size: 13)).position(x: size - 8, y: 8)
            }
        }
        .frame(width: size, height: size)
        .background {
            // outer shadows: front 0 0 0 3px #fff over 0 4px 0 rgba(0,0,0,.14); back 0 2px 0 rgba(0,0,0,.14)
            ZStack {
                shape.fill(.black.opacity(0.14)).offset(y: front ? 4 : 2)
                if front {
                    RoundedRectangle(cornerRadius: 17, style: .circular).fill(.white).padding(-3)
                }
            }
        }
    }
}

/// White Lilita One digits with four 1.5-point outline shadows and a 3-point drop shadow (the nest text-shadow).
struct OutlinedNumber: View {
    let text: String
    let size: CGFloat

    var body: some View {
        let base = Text(text).font(Theme.display(size)).tracking(size * 0.01)
        let edge = Color(red: 40 / 255, green: 24 / 255, blue: 14 / 255)
        ZStack {
            base.foregroundStyle(edge.opacity(0.45)).offset(y: 3)
            base.foregroundStyle(edge.opacity(0.6)).offset(x: -1.5, y: -1.5)
            base.foregroundStyle(edge.opacity(0.6)).offset(x: 1.5, y: -1.5)
            base.foregroundStyle(edge.opacity(0.6)).offset(x: -1.5, y: 1.5)
            base.foregroundStyle(edge.opacity(0.6)).offset(x: 1.5, y: 1.5)
            base.foregroundStyle(.white)
        }
        .fixedSize()
    }
}

// MARK: - Lanes (.lanes)

private struct Lanes: View {
    /// How much of the fourth row of waiting nests shows under the first three.
    static let peek: CGFloat = 0.45
    @ObservedObject var model: GameModel
    let width: CGFloat
    /// The lane box's height, short of the full three rows and a bit when the screen is tight.
    var height: CGFloat = .infinity

    var body: some View {
        let cols: CGFloat = CGFloat(max(1, model.side.columns))
        let laneW: CGFloat = (width - (cols - 1) * 6) / cols         // same as a holding slot
        let nest: CGFloat = laneW * 0.88                             // .lanes .nest{width:88%}
        // Three whole rows plus the top of the fourth; its lower half of that fades out (JS fitLanes).
        let rows: CGFloat = 3 * nest + 18 + nest * Lanes.peek
        let maxH: CGFloat = min(CGFloat(JSRound(Double(rows))), height)
        let fade: CGFloat = CGFloat(JSRound(Double(nest * 0.1)))
        let boxH: CGFloat = maxH + 12
        HStack(alignment: .top, spacing: 10) {
            ForEach(model.side.lanes) { lane in
                LaneColumn(model: model, lane: lane, laneW: laneW, nest: nest)
            }
        }
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32), value: model.side.lanes.map(\.id))
        .padding(.top, 12 + 4.0 / 3)   // measured against the web version on device
        .padding(.horizontal, 12)
        .frame(width: width + 24, height: boxH, alignment: .top)
        .clipped()
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: (boxH - fade) / boxH),
                                   .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
        }
        .padding(.top, -12)
        .padding(.horizontal, -12)
    }
}

/// One lane. Like the page's `pointerdown` handler, it taps the moment a finger lands, not when it lifts, so a press
/// is never lost while the lanes redraw and the game feels as quick as the web version.
private struct LaneColumn: View {
    @ObservedObject var model: GameModel
    let lane: SideState.Lane
    let laneW: CGFloat
    let nest: CGFloat
    @SwiftUI.State private var down = false

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(lane.nests.enumerated()), id: \.offset) { k, n in
                NestTile(color: model.hex(n.c), count: n.n, size: nest, fontSize: k == 0 ? 23 : 21,
                         front: k == 0, key: n.key)
                    .overlay(alignment: .topTrailing) {
                        if k < lane.at.count, let q = model.queuePlace(lane: lane.id, at: lane.at[k]) {
                            QueueBadge(place: q).offset(x: 8, y: -8)
                        }
                    }
            }
        }
        .frame(width: laneW)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !down {
                    down = true
                    // Which nest the finger landed on: rows are a nest tall with 6 points between them.
                    let k = min(max(0, Int(v.startLocation.y / (nest + 6))), lane.at.count - 1)
                    if k >= 0 { model.press(lane: lane.id, at: lane.at[k]) }
                }
            }
            .onEnded { _ in down = false })
    }
}

/// `.lanes .nest .qbadge`: the nest's place in the queue, a gold disc with a white ring.
private struct QueueBadge: View {
    let place: Int

    var body: some View {
        Text("\(place)")
            .font(Theme.display(14))
            .foregroundStyle(Color(hex: 0x3A2A00))
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(Capsule().fill(Theme.gold))
            .background(Capsule().fill(.white).padding(-3))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
            .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Tool bar (.toolbar)

/// The tool bar on a wooden tray, slid up from the bottom of the screen over the lanes while the backpack is open.
private struct ToolTray: View {
    var body: some View {
        ToolBar()
            .padding(EdgeInsets(top: 16, leading: 14, bottom: 10, trailing: 14))
            .frame(maxWidth: .infinity)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                    .fill(Color(hex: 0xE3B886))
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                        .stroke(Color(hex: 0xC9965E), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.22), radius: 8, y: -2)
                    .ignoresSafeArea(edges: .bottom))
    }
}

/// The five tools, shown as on a new player's page: none owned yet, each with a yellow "+" to get more.
/// (They aren't playable yet.)
private struct ToolBar: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach(["🦉", "🔍", "🌰", "slot", "🪄"], id: \.self) { t in
                ZStack(alignment: .topTrailing) {
                    Group {
                        if t == "slot" {
                            Text("+")
                                .font(Theme.body(28 * 0.78, 900))
                                .foregroundStyle(Theme.darkInk)
                                .offset(y: -0.06 * 28 * 0.78)
                                .frame(width: 28, height: 28)
                                .background(RoundedRectangle(cornerRadius: 28 * 0.28).fill(.white))
                                .overlay(RoundedRectangle(cornerRadius: 28 * 0.28).strokeBorder(Theme.darkInk, lineWidth: 3))
                        } else {
                            Text(t).font(.system(size: 26))
                        }
                    }
                    .saturation(0.4)
                    .opacity(0.5)
                    .frame(width: 52, height: 46)
                    .background(RoundedRectangle(cornerRadius: 15, style: .circular).fill(Color(hex: 0xF3F0E6)))
                    .background(RoundedRectangle(cornerRadius: 15, style: .circular).fill(.black.opacity(0.14)).offset(y: 3))
                    Text("+")
                        .font(Theme.body(13, 800))
                        .foregroundStyle(Color(hex: 0x3A2A00))
                        .frame(minWidth: 24, minHeight: 24)
                        .background(Circle().fill(Theme.gold))
                        .background(Circle().fill(.white).padding(-2))
                        .offset(x: 7, y: -7)
                }
            }
        }
    }
}

/// Buttons nudge down a little while pressed.
struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.offset(y: configuration.isPressed ? 2 : 0)
    }
}
