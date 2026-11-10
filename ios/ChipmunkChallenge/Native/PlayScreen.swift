import ChipmunkEngine
import SwiftUI

/// The play screen, laid out like the web page's `.game` card: the title bar and buttons, then the wooden stage with
/// the HUD, the board, the holding slots, the lanes of nests and the tool bar. Sizes come from the page's CSS.
struct PlayScreen: View {
    @ObservedObject var model: GameModel
    /// Where the win card's reward and the coin counter are, for the coins flying between them.
    @SwiftUI.State private var rewardAt: CGRect?
    @SwiftUI.State private var coinChipAt: CGRect?
    static let space = "play"

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
                // The tray slides up to show and back down to hide, however it's closed (backpack, board tap, or
                // using a tool). The zIndex keeps it in place in the ZStack while it slides out.
                if model.toolsOpen && model.status == .playing {
                    ToolTray(model: model)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom))
                        .zIndex(1)
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
                    if let t = model.shopTool {
                        ToolShop(model: model, tool: t)
                    }
                    if model.heartsCardShown {
                        OutOfHearts(model: model)
                    }
                    if let run = model.scene {
                        SceneLayer(model: model, run: run).id(run.id)
                    } else if model.status == .building && !model.heartsCardShown {
                        ProgressView().controlSize(.large).tint(Theme.ink)
                    } else if case .failed = model.status {
                        ResultCard(model: model)
                    }
                    // The win scene shows the coin counter over its sky, so the kiss's coins have somewhere to land.
                    if model.scene?.kind == .win {
                        if island {
                            StatusRow(model: model, island: 126, screenWidth: geo.size.width,
                                      corner: displayCornerRadius(geo.size.width + geo.safeAreaInsets.leading
                                                                  + geo.safeAreaInsets.trailing))
                                .offset(y: 29.5 - Chip<EmptyView>.height / 2 - geo.safeAreaInsets.top)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .allowsHitTesting(false)
                        } else {
                            StatusRow(model: model)
                                .padding(EdgeInsets(top: 10, leading: 6, bottom: 0, trailing: 6))
                                .frame(width: w)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .allowsHitTesting(false)
                        }
                    }
                    // Coins fly to the counter: from the kiss in the win scene, or from the win card's reward if the
                    // scene was skipped before the kiss.
                    if model.status == .won, model.coinsWaiting, let to = coinChipAt {
                        if let kiss = model.kissCoinsAt {
                            CoinFlight(model: model, from: CGRect(origin: kiss, size: .zero), to: to, burst: true)
                                .id(model.winCount)
                        } else if model.cardShown, let from = rewardAt {
                            CoinFlight(model: model, from: from, to: to)
                                .id(model.winCount)
                        }
                    }
                }
                .zIndex(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .coordinateSpace(name: PlayScreen.space)
            .onPreferenceChange(RewardFrame.self) { rewardAt = $0 }
            .onPreferenceChange(CoinChipFrame.self) { coinChipAt = $0 }
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
    /// The icon in a slowly turning rainbow (the backpack).
    var rainbow = false
    /// A red notification dot (a mystery box waiting); it pops each time `badgePop` changes.
    var badge = false
    var badgePop = 0
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let rainbowColors = [0xFF4D4D, 0xFFA53A, 0xFFE14D, 0x5FD35F, 0x4DC3FF, 0x6B6BFF, 0xC065FF, 0xFF4D4D]
        .map { Color(hex: UInt32($0)) }

    var body: some View {
        Button(action: action) {
            Group {
                if rainbow {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
                        let turn = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate / 3 * 360
                        icon.fill(AngularGradient(colors: Self.rainbowColors, center: .center,
                                                  angle: .degrees(turn.truncatingRemainder(dividingBy: 360))),
                                  style: FillStyle(eoFill: true))
                    }
                } else {
                    icon.fill(on ? Theme.gold : Theme.ink, style: FillStyle(eoFill: true))
                }
            }
                .frame(width: size, height: size)
                .frame(width: HUDButton.diameter, height: HUDButton.diameter)
                .background(Circle().fill(on ? Theme.darkInk : .white.opacity(0.88))
                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1))
        }
        .buttonStyle(Pressable())
        .overlay(alignment: .topTrailing) {
            if badge {
                BadgeDot(pop: badgePop)
                    .offset(x: 2, y: -2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: badge)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

/// The backpack's notification dot: red with a white ring, popping when a new box arrives.
private struct BadgeDot: View {
    let pop: Int
    @SwiftUI.State private var scale: CGFloat = 1

    var body: some View {
        Circle()
            .fill(Color(hex: 0xE53935))
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .frame(width: 13, height: 13)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            .scaleEffect(scale)
            .onChange(of: pop) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { scale = 1.5 }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.15)) { scale = 1 }
            }
            .accessibilityHidden(true)
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
        // The extra slot (Add a Nest) doesn't change the slot size, so the layout doesn't jump when it's added.
        let n = CGFloat(max(1, model.side.slots.count - (model.extraUsed ? 1 : 0)))
        let cols = CGFloat(max(1, model.side.columns))
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
                .overlay(alignment: .top) { BoardNotice(model: model).padding(.top, 6) }
                .onAppear { model.cellSize = cs }
                .onChange(of: cs) { _, v in model.cellSize = v }
            VStack(spacing: 12) {
                Slots(model: model, width: laneW, maxWidth: width - 16)
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
/// the island's edge and where the screen's rounded corner actually is at the island's mid-height (the same spot iOS
/// centers the clock on); otherwise they sit at the row's ends.
struct StatusRow: View {
    @ObservedObject var model: GameModel
    @SwiftUI.State private var pop: CGFloat = 1
    var island: CGFloat? = nil
    var screenWidth: CGFloat = 0
    var corner: CGFloat = 0

    /// The island's vertical center, in points from the top of the screen (it spans 11 to 48 on current phones).
    static let islandMidY: CGFloat = 29.5

    /// How far in from the left (or right) edge to center something beside the island: halfway between the island's
    /// edge and where the screen's rounded corner is at the island's mid-height (the same spot iOS centers the clock on).
    static func sideCenter(screenWidth: CGFloat, island: CGFloat, corner: CGFloat) -> CGFloat {
        let edge = (screenWidth - island) / 2
        // The corner curve's x at the island's mid-height: a circle of radius `corner` in the top-left corner.
        let dy = max(0, corner - islandMidY)
        let curve = corner - (max(0, corner * corner - dy * dy)).squareRoot()
        return (curve + edge) / 2
    }

    var body: some View {
        Group {
            if let island {
                let x = StatusRow.sideCenter(screenWidth: screenWidth, island: island, corner: corner)
                ZStack {
                    hearts.position(x: x, y: Chip<EmptyView>.height / 2)
                    coins.position(x: screenWidth - x, y: Chip<EmptyView>.height / 2)
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
            // The heart chip also holds the refill clock while hearts are below 5.
            Chip(leading: 9, trailing: 12) {
                HStack(spacing: 4) {
                    Icons.heart
                        .fill(model.hearts > 0 ? Color(hex: 0xE53935) : Color(hex: 0xBDBDBD))
                        .overlay(Icons.heart.stroke(model.hearts > 0 ? Color(hex: 0x9C1F1D) : Color(hex: 0x8A8A8A),
                                                    lineWidth: 1.4 * 15 / 24))
                        .frame(width: 19, height: 18)
                        .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
                    Text("\(model.hearts)")
                    if !model.heartClock.isEmpty {
                        Text(model.heartClock)
                            .font(Theme.body(12, 800))
                            .monospacedDigit()
                            .foregroundStyle(Color(hex: 0x5D6B54))
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.hearts) of \(GameModel.heartMax) hearts"
                                + (model.heartClock.isEmpty ? "" : ". Next heart in \(model.heartClock)"))
    }

    private var coins: some View {
            Chip(leading: 5, trailing: 10) {
                HStack(spacing: 4) {
                    CoinIcon().frame(width: 20, height: 20)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: CoinChipFrame.self, value: g.frame(in: .named(PlayScreen.space)))
                        })
                    Text(model.coinsShown.formatted())
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(model.coinsShown)))
                }
            }
            .scaleEffect(pop)
            .onChange(of: model.coinLanded) { _, _ in
                withAnimation(.easeOut(duration: 0.08)) { pop = 1.12 }
                withAnimation(.easeIn(duration: 0.14).delay(0.08)) { pop = 1 }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.coinsShown) coins")
    }
}

/// Restart (after a confirmation), undo and fast on the left; the level number centered between them; the backpack
/// (which shows the tools, in a turning rainbow, with a red dot while a mystery box waits), home and settings on the
/// right.
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
            Spacer(minLength: 2)
            HUDButton(icon: Icons.backpack, on: model.toolsOpen || model.magicMode || model.peek, rainbow: true,
                      badge: !model.held.isEmpty && !model.helped, badgePop: model.heldPop) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { model.toggleBackpack() }
            }
            HUDButton(icon: Icons.home) { withAnimation(.easeOut(duration: 0.2)) { model.goHome() } }
            HUDButton(icon: Icons.gear, size: 19) { model.settingsOpen = true }
        }
        // The level, in a bubble centered on the screen (under the Dynamic Island), between the two button groups.
        .overlay { LevelTag(model: model) }
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
    /// How wide the row may grow with the extra slot (nearly the screen's width).
    let maxWidth: CGFloat

    var body: some View {
        // Slots keep the size they have without the extra slot; the extra one makes the row wider, out toward the
        // screen's edges, and only if six of that size don't fit do they shrink (just enough).
        let n = max(1, model.side.slots.count)
        let base = max(1, n - (model.extraUsed ? 1 : 0))
        let size = min((width - CGFloat(base - 1) * 6) / CGFloat(base), (maxWidth - CGFloat(n - 1) * 6) / CGFloat(n))
        let rowW = CGFloat(n) * size + CGFloat(n - 1) * 6
        HStack(spacing: 6) {
            ForEach(0..<n, id: \.self) { k in
                let item = k < model.side.slots.count ? model.side.slots[k] : nil
                if let item {
                    NestTile(color: model.hex(item.c), count: item.r, size: size, fontSize: 26, front: false, key: item.key)
                        .overlay {
                            if item.magic { MagicGlow(radius: 14) }
                            else if model.magicMode { WandTarget(radius: 14) }
                        }
                        .onTapGesture { model.wandSlot(k) }
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
        .frame(width: rowW)
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
        let columns = HStack(alignment: .top, spacing: 10) {
            ForEach(model.side.lanes) { lane in
                LaneColumn(model: model, lane: lane, laneW: laneW, nest: nest, scrolling: model.peek)
            }
        }
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32), value: model.side.lanes.map(\.id))
        .padding(.top, 12 + 4.0 / 3)   // measured against the web version on device
        .padding(.horizontal, 12)
        Group {
            if model.peek {
                // Magnifying glass: every waiting nest, scrolling. A tap (not a scroll) still loads or queues a nest.
                ScrollView(.vertical) { columns.padding(.bottom, 16) }
                    .frame(width: width + 24, height: boxH)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0x1E88E5).opacity(0.10)).padding(.horizontal, 8))
            } else {
                columns
                    .frame(width: width + 24, height: boxH, alignment: .top)
                    .clipped()
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: (boxH - fade) / boxH),
                                               .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                    }
            }
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
    /// Inside the magnifying glass's scroll view: a tap, not a touch-down, so the finger can scroll.
    var scrolling = false
    @SwiftUI.State private var down = false

    var body: some View {
        let column = VStack(spacing: 6) {
            ForEach(Array(lane.nests.enumerated()), id: \.offset) { k, n in
                let at = k < lane.at.count ? lane.at[k] : -1
                NestTile(color: model.hex(n.c), count: n.n, size: nest, fontSize: k == 0 ? 23 : 21,
                         front: k == 0, key: n.key)
                    .overlay {
                        if model.magicMode { WandTarget(radius: 14) }
                        if let o = model.owlPlan.firstIndex(of: GameModel.Queued(l: lane.id, i: at)) {
                            OwlRing(now: o == 0)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if let q = model.queuePlace(lane: lane.id, at: at) {
                            QueueBadge(place: q).offset(x: 8, y: -8)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if let o = model.owlPlan.firstIndex(of: GameModel.Queued(l: lane.id, i: at)) {
                            OwlBadge(step: o + 1).offset(x: -6, y: -6)
                        }
                    }
            }
        }
        .frame(width: laneW)
        .contentShape(Rectangle())
        if scrolling {
            column.onTapGesture(coordinateSpace: .local) { p in pressAt(p.y) }
        } else {
            column.gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !down {
                        down = true
                        pressAt(v.startLocation.y)
                    }
                }
                .onEnded { _ in down = false })
        }
    }

    /// Which nest the finger landed on: rows are a nest tall with 6 points between them.
    private func pressAt(_ y: CGFloat) {
        guard !lane.at.isEmpty else { return }
        let k = min(max(0, Int(y / (nest + 6))), lane.at.count - 1)
        model.press(lane: lane.id, at: lane.at[k])
    }
}

/// Wise Owl: a brown ring round each nest in the plan; the next one to tap pulses gold.
private struct OwlRing: View {
    let now: Bool
    @SwiftUI.State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .circular)
            .strokeBorder(now && pulse ? Theme.gold : Color(hex: 0x8D5A2B), lineWidth: now && pulse ? 5 : 3)
            .shadow(color: now && pulse ? Color(hex: 0xFFD23F).opacity(0.8) : .clear, radius: 7)
            .padding(-3)
            .onAppear {
                guard now, !UIAccessibility.isReduceMotionEnabled else { return }
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { pulse = true }
            }
            .allowsHitTesting(false)
    }
}

/// `.owlbadge`: the step number on a brown pill with a little owl.
private struct OwlBadge: View {
    let step: Int
    var body: some View {
        HStack(spacing: 1) {
            Text("🦉").font(.system(size: 11))
            Text("\(step)").font(Theme.body(13, 800)).foregroundStyle(.white)
        }
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .frame(height: 22)
        .background(Capsule().fill(Color(hex: 0x8D5A2B)))
        .background(Capsule().fill(.white).padding(-2))
        .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
        .allowsHitTesting(false)
    }
}

/// While the wand is armed every nest it can touch shimmers in rainbow colors.
private struct WandTarget: View {
    let radius: CGFloat
    var body: some View {
        TimelineView(.animation(paused: UIAccessibility.isReduceMotionEnabled)) { tl in
            let a = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2 * 360
            RoundedRectangle(cornerRadius: radius, style: .circular)
                .strokeBorder(AngularGradient(colors: Rainbow.colors, center: .center, angle: .degrees(a)), lineWidth: 3.5)
                .padding(-3)
        }
        .allowsHitTesting(false)
    }
}

/// A magic nest in a slot: a soft rainbow rim.
private struct MagicGlow: View {
    let radius: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .circular)
            .strokeBorder(AngularGradient(colors: Rainbow.colors, center: .center), lineWidth: 3)
            .opacity(0.9)
            .allowsHitTesting(false)
    }
}

enum Rainbow {
    static let colors = [0xE53935, 0xFB8C00, 0xFDD835, 0x43A047, 0x1E88E5, 0x8E24AA, 0xE53935].map { Color(hex: UInt32($0)) }
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
/// Tapping a tool asks first (a small ✓ / ✕ bubble over the tray); the wand arms straight away.
private struct ToolTray: View {
    @ObservedObject var model: GameModel
    @SwiftUI.State private var asking: Tool?

    var body: some View {
        VStack(spacing: 10) {
            if !model.held.isEmpty {
                // Why the backpack has a red dot.
                HStack(spacing: 8) {
                    MysteryBoxIcon(size: 24, grey: model.helped)
                    Text(model.helped
                         ? "Mystery box lost: a tool or Continue was used on this try."
                         : (model.held.count > 1 ? "\(model.held.count) mystery boxes" : "A mystery box")
                            + " waiting. Clear the board without tools to open " + (model.held.count > 1 ? "them." : "it."))
                        .font(Theme.body(13, 800))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(hex: model.helped ? 0xEEEEEE : 0xFFF8E1)))
                .padding(.horizontal, 14)
            }
            if let t = asking {
                ToolAsk(tool: t) {
                    asking = nil
                } yes: {
                    asking = nil
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { model.use(t) }
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            ToolBar(model: model, asking: asking) { t in
                if asking == t {
                    asking = nil
                } else if model.count(t) > 0 && model.canUse(t) && t != .wand {
                    asking = t
                    model.lightTap()
                } else if t == .wand && model.count(t) > 0 && model.canUse(t) {
                    asking = nil
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { model.use(t) }
                } else {
                    asking = nil
                    model.toolTapped(t)
                }
            }
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
        .animation(.easeOut(duration: 0.16), value: asking)
        .onChange(of: model.toolsOpen) { _, open in if !open { asking = nil } }
    }
}

/// `.toolask`: the tool, ✕ and ✓, on a white pill.
private struct ToolAsk: View {
    let tool: Tool
    let no: () -> Void
    let yes: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ToolIcon(tool: tool, size: 26)
            Text("Use \(tool.name)?")
                .font(Theme.body(15, 800))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Button(action: no) {
                Text("✕").font(.system(size: 20, weight: .black)).foregroundStyle(Color(hex: 0x555555))
                    .frame(width: 44, height: 44).background(Circle().fill(Color(hex: 0xE9E9E9)))
            }
            .accessibilityLabel("Cancel")
            Button(action: yes) {
                Text("✓").font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Circle().fill(Color(hex: 0x2E7D32)))
            }
            .accessibilityLabel("Use \(tool.name)")
        }
        .buttonStyle(Pressable())
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 8))
        .background(Capsule().fill(.white).shadow(color: .black.opacity(0.25), radius: 9, y: 6))
        .overlay(Capsule().strokeBorder(Theme.darkInk, lineWidth: 2))
    }
}

/// A tool's picture: its emoji, or for the Extra Slot a plus inside a slot-shaped box.
struct ToolIcon: View {
    let tool: Tool
    var size: CGFloat = 26

    var body: some View {
        if tool == .slot {
            let box = size * 28 / 26
            Text("+")
                .font(Theme.body(box * 0.78, 900))
                .foregroundStyle(Theme.darkInk)
                .offset(y: -0.06 * box * 0.78)
                .frame(width: box, height: box)
                .background(RoundedRectangle(cornerRadius: box * 0.28).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: box * 0.28).strokeBorder(Theme.darkInk, lineWidth: box * 3 / 28))
        } else {
            Text(tool.icon).font(.system(size: size))
        }
    }
}

/// The five tools (`.toolbar`): each shows how many are left, or a yellow "+" with none (tap to buy more).
private struct ToolBar: View {
    @ObservedObject var model: GameModel
    let asking: Tool?
    let tap: (Tool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Tool.allCases) { t in
                let n = model.count(t)
                let on = (t == .wand && model.magicMode) || (t == .peek && model.peek)
                let empty = n == 0 && !on
                let spent = n > 0 && !model.canUse(t) && !on
                Button { tap(t) } label: {
                    ZStack(alignment: .topTrailing) {
                        ToolIcon(tool: t)
                            .saturation(empty ? 0.4 : 1)
                            .opacity(empty ? 0.5 : 1)
                            .frame(width: 52, height: 46)
                            .background {
                                let shape = RoundedRectangle(cornerRadius: 15, style: .circular)
                                if on {
                                    shape.fill(LinearGradient(colors: Rainbow.colors, startPoint: .leading, endPoint: .trailing))
                                } else {
                                    shape.fill(empty ? Color(hex: 0xF3F0E6) : .white)
                                }
                            }
                            .overlay {
                                if asking == t {
                                    RoundedRectangle(cornerRadius: 15, style: .circular).strokeBorder(Color(hex: 0x2E7D32), lineWidth: 3)
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 15, style: .circular).fill(.black.opacity(0.14)).offset(y: 3))
                        Text(n > 0 ? "\(n)" : "+")
                            .font(Theme.body(13, 800))
                            .foregroundStyle(n > 0 ? .white : Color(hex: 0x3A2A00))
                            .padding(.horizontal, 6)
                            .frame(minWidth: 24, minHeight: 24)
                            .background(Capsule().fill(n > 0 ? Theme.darkInk : Theme.gold))
                            .background(Capsule().fill(.white).padding(-2))
                            .offset(x: 7, y: -7)
                    }
                    .opacity(spent ? 0.45 : 1)
                }
                .buttonStyle(Pressable())
                .accessibilityLabel("\(t.name): \(n) left. \(t.desc)")
            }
        }
    }
}

/// A tool's shop card, opened by tapping a tool with none left (JS openToolShop).
private struct ToolShop: View {
    @ObservedObject var model: GameModel
    let tool: Tool

    var body: some View {
        let can = model.coins >= tool.price
        ZStack {
            Color(red: 20 / 255, green: 30 / 255, blue: 15 / 255, opacity: 0.5)
                .ignoresSafeArea()
                .onTapGesture { model.shopTool = nil }
            VStack(spacing: 10) {
                ToolIcon(tool: tool, size: 44)
                    .shadow(color: Color(hex: 0xFFF59D), radius: 8)
                Text(tool.name + (tool.pack > 1 ? " ×\(tool.pack)" : ""))
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.ink)
                Text(tool.desc)
                    .font(Theme.body(15, 500))
                    .foregroundStyle(Color(hex: 0x4A5841))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button { model.buy(tool) } label: {
                        HStack(spacing: 4) {
                            CoinIcon().frame(width: 18, height: 18)
                            Text(tool.price.formatted())
                        }
                        .bigLabel(alt: false)
                    }
                    .disabled(!can)
                    .opacity(can ? 1 : 0.45)
                    Button { model.shopTool = nil } label: { Text("Not now").bigLabel(alt: true) }
                }
                .buttonStyle(Pressable())
                .padding(.top, 4)
                Text(can ? "You have \(model.coins.formatted()) coins."
                         : "You need \((tool.price - model.coins).formatted()) more coins.")
                    .font(Theme.body(13, 800))
                    .foregroundStyle(Color(hex: 0x4A5841))
            }
            .padding(20)
            .frame(maxWidth: 340)
            .background(RoundedRectangle(cornerRadius: 20, style: .circular).fill(.white)
                .shadow(color: .black.opacity(0.3), radius: 15, y: 10))
            .padding(16)
        }
        .transition(.opacity)
    }
}

/// Over the top of the board: the armed wand or the open magnifying glass (with a button to put it away), or else
/// the latest short message.
private struct BoardNotice: View {
    @ObservedObject var model: GameModel

    var body: some View {
        Group {
            if model.magicMode {
                pill("🪄 Tap a nest to make it magic", button: "Cancel") { model.cancelWand() }
            } else if model.peek {
                pill("🔍 Scroll to look ahead", button: "Done") { model.toolTapped(.peek) }
            } else if let t = model.toast {
                pill(t.text, button: nil, action: nil).id(t.id)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
        .animation(.easeOut(duration: 0.2), value: model.magicMode)
        .animation(.easeOut(duration: 0.2), value: model.peek)
    }

    private func pill(_ text: String, button: String?, action: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(Theme.body(14, 800))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let button, let action {
                Button(action: action) {
                    Text(button)
                        .font(Theme.body(13, 800))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Capsule().fill(Theme.darkInk))
                }
                .buttonStyle(Pressable())
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, button == nil ? 14 : 5)
        .padding(.vertical, button == nil ? 8 : 5)
        .background(Capsule().fill(.white.opacity(0.95)).shadow(color: .black.opacity(0.2), radius: 6, y: 3))
        .padding(.horizontal, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Buttons nudge down a little while pressed.
struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.offset(y: configuration.isPressed ? 2 : 0)
    }
}

// MARK: - Level tag, coins, hearts

/// The level in play ("Level 20", "Challenge 8", "Day 41"), in a bubble centered under the Dynamic Island.
private struct LevelTag: View {
    @ObservedObject var model: GameModel

    var body: some View {
        let text: String = switch model.mode {
        case .level: "Level \(model.boardIndex + (model.status == .won ? 0 : 1))"
        case .mining: "Challenge \(model.paraRound + (model.status == .won ? 0 : 1))"
        case .daily: "Day \(model.dayCount)"
        }
        Text(text)
            .font(Theme.display(18))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(.white.opacity(0.9)).shadow(color: .black.opacity(0.12), radius: 1.5, y: 1))
            .opacity(model.level == nil ? 0 : 1)
            .allowsHitTesting(false)
    }
}

struct RewardFrame: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

struct CoinChipFrame: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

/// The win card's coins fly from the reward up to the coin counter, which counts up as each one lands.
private struct CoinFlight: View {
    @ObservedObject var model: GameModel
    let from: CGRect
    let to: CGRect
    /// From the kiss: the coins first pop out in a ring around it, then fly to the counter.
    var burst = false
    @SwiftUI.State private var popped = false
    @SwiftUI.State private var flying: [Bool] = Array(repeating: false, count: CoinFlight.count)
    @SwiftUI.State private var landed: [Bool] = Array(repeating: false, count: CoinFlight.count)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let count = 12

    var body: some View {
        ZStack {
            ForEach(0..<Self.count, id: \.self) { k in
                // Each coin starts at the reward with a little spread (or pops out around the kiss) and flies to the
                // counter.
                let spread = CGFloat(k % 4) * 9 - 13
                let a = Double(k) / Double(Self.count) * 2 * .pi - .pi / 2
                let ring = CGPoint(x: from.midX + CGFloat(cos(a)) * (44 + CGFloat(k % 3) * 12),
                                   y: from.midY + CGFloat(sin(a)) * (34 + CGFloat(k % 3) * 10) - 20)
                let start = burst ? (popped ? ring : CGPoint(x: from.midX, y: from.midY))
                    : CGPoint(x: from.minX + 15 + spread, y: from.midY)
                CoinIcon()
                    .frame(width: 26, height: 26)
                    .scaleEffect(flying[k] ? 0.75 : burst && !popped ? 0.3 : 1)
                    .opacity(landed[k] ? 0 : 1)
                    .position(flying[k] ? CGPoint(x: to.midX, y: to.midY) : start)
                    .opacity(flying[k] || k == 0 || burst ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
        .task {
            if reduceMotion {
                model.countCoins(1)
                return
            }
            if burst {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { popped = true }
                try? await Task.sleep(for: .milliseconds(380))
            } else {
                try? await Task.sleep(for: .milliseconds(450))
            }
            for k in 0..<Self.count {
                withAnimation(.easeIn(duration: 0.55)) { flying[k] = true }
                let i = k
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(550))
                    landed[i] = true
                    model.countCoins(Double(i + 1) / Double(Self.count))
                }
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
    }
}

/// Out of hearts (Level Play): when the next heart comes, or 5 hearts for 500 coins.
private struct OutOfHearts: View {
    @ObservedObject var model: GameModel

    var body: some View {
        let can = model.coins >= GameModel.heartsPrice
        ZStack {
            Color(red: 20 / 255, green: 30 / 255, blue: 15 / 255, opacity: 0.55)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                Text("Out of hearts")
                    .font(Theme.display(30))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 4) {
                    ForEach(0..<GameModel.heartMax, id: \.self) { k in
                        Icons.heart
                            .fill(k < model.hearts ? Color(hex: 0xE53935) : Color(hex: 0xD6D6D6))
                            .overlay(Icons.heart.stroke(Color(hex: 0x8A8A8A), lineWidth: 1))
                            .frame(width: 26, height: 24)
                    }
                }
                .accessibilityHidden(true)
                Text(model.heartClock.isEmpty ? "A heart is ready." : "Next heart in \(model.heartClock)")
                    .font(Theme.body(16, 800))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: 0x4A5841))
                Text("Hearts come back one every 10 minutes, up to 5.")
                    .font(Theme.body(13, 600))
                    .foregroundStyle(Color(hex: 0x5D6B54))
                    .multilineTextAlignment(.center)
                Button { model.buyHearts() } label: {
                    HStack(spacing: 0) {
                        Text("Get 5 hearts ")
                        CoinIcon().frame(width: 18, height: 18).padding(.leading, 6).padding(.trailing, 4)
                        Text(GameModel.heartsPrice.formatted())
                    }
                    .bigLabel(alt: false)
                }
                .buttonStyle(Pressable())
                .disabled(!can)
                .opacity(can ? 1 : 0.45)
                .padding(.top, 4)
                if !can {
                    Text("You need \((GameModel.heartsPrice - model.coins).formatted()) more coins.")
                        .font(Theme.body(13, 800))
                        .foregroundStyle(Color(hex: 0x4A5841))
                }
                Button { withAnimation(.easeOut(duration: 0.2)) { model.closeHeartsCard() } } label: {
                    Text("Home").bigLabel(alt: true)
                }
                .buttonStyle(Pressable())
            }
            .padding(20)
            .frame(maxWidth: 340)
            .background(RoundedRectangle(cornerRadius: 20, style: .circular).fill(.white)
                .shadow(color: .black.opacity(0.3), radius: 15, y: 10))
            .padding(16)
        }
        .transition(.opacity)
        .onChange(of: model.hearts) { _, h in
            // A heart came back while the card was up: carry on.
            if h > 0 { model.heartArrived() }
        }
    }
}
