import ChipmunkEngine
import SceneKit
import SwiftUI
import UIKit

// MARK: - 3D scene layer (.win3d)

/// The page's `.win3d` layer over the stage: a sky gradient, the 3D scene, the level splash title (intro) and
/// "Tap to skip". Plays the model's current scene, then fades out over .6s while the card appears underneath.
struct SceneLayer: View {
    @ObservedObject var model: GameModel
    let run: GameModel.SceneRun
    @SwiftUI.State private var fading = false
    /// The intro waits on its Start button.
    @SwiftUI.State private var started = false

    /// The 3D ground's color as rendered (flat toon shading), so the grass can run on below the scene.
    static let grass = Color(hex: 0xBBF47A)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = min(geo.size.height, w * (run.kind == .win ? 1.05 : 1.1))
            ZStack {
                LinearGradient(stops: [.init(color: Color(hex: 0xBFE3FF), location: 0), .init(color: Color(hex: 0xE3F4FF), location: 0.55),
                                       .init(color: Color(hex: 0xF5FBEF), location: 1)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                if run.kind != .win {
                    // The scene is centered, so the grass below it is half the leftover height plus the bottom inset.
                    SceneLayer.grass
                        .frame(height: (geo.size.height - h) / 2 + 1 + geo.safeAreaInsets.bottom)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .offset(y: geo.safeAreaInsets.bottom)
                }
                SceneCanvas(run: run, size: CGSize(width: w, height: h), ready: { model.introReady },
                            go: run.kind == .intro ? { started } : nil) {
                    finish()
                }
                .frame(width: w, height: h)
                if run.kind == .intro && model.introReady && !started {
                    // Centered on the grass below the scene, down to the screen's bottom edge.
                    StartButton { started = true }
                        .frame(height: max(80, (geo.size.height - h) / 2 + geo.safeAreaInsets.bottom))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .offset(y: geo.safeAreaInsets.bottom)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                if run.kind == .intro {
                    SplashTitle(model: model)
                        .padding(.horizontal, 12)
                        // Lower than the web layout's 18: clear of the home button and closer to the chipmunk.
                        .padding(.top, 18 - 2.0 / 3 + (geo.size.height * 0.06).rounded())
                        .frame(maxHeight: .infinity, alignment: .top)
                    // Back out to the home screen without starting; the board waits, and it doesn't count as a try.
                    // Beside a Dynamic Island it sits centered between the island and the screen's rounded corner (where
                    // the coins chip goes), a little below the island's row; elsewhere it sits in from the top-right corner.
                    let home = HUDButton(icon: Icons.home) { withAnimation(.easeOut(duration: 0.2)) { model.goHome() } }
                        .accessibilityLabel("Home")
                    if geo.safeAreaInsets.top >= 55 {
                        let x = StatusRow.sideCenter(screenWidth: w, island: 126,
                                                     corner: displayCornerRadius(w + geo.safeAreaInsets.leading
                                                                                 + geo.safeAreaInsets.trailing))
                        home.position(x: w - x, y: StatusRow.islandMidY - geo.safeAreaInsets.top + 12)
                    } else {
                        home.padding(.top, 10)
                            .padding(.trailing, 16)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                } else {
                    Text("Tap to skip")
                        .font(Theme.body(12, 800))
                        .foregroundStyle(Color(red: 31 / 255, green: 42 / 255, blue: 24 / 255, opacity: 0.55))
                        .padding(.bottom, 12)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .animation(.interpolatingSpring(stiffness: 260, damping: 16), value: model.introReady)
        .opacity(fading ? 0 : 1)
        .allowsHitTesting(!fading)
    }

    private func finish() {
        model.sceneFinished(run)
        withAnimation(.easeInOut(duration: 0.6)) { fading = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { model.sceneGone(run) }
    }
}

/// The intro's Start button: a big dark pill, centered on the grass.
private struct StartButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Start")
                .font(Theme.display(30))
                .tracking(0.5)
                .foregroundStyle(.white)
                .padding(.vertical, 14)
                .padding(.horizontal, 64)
                .background(Capsule().fill(Theme.darkInk).shadow(color: .black.opacity(0.25), radius: 0, y: 4))
        }
        .buttonStyle(Pressable())
    }
}

/// `.splash-title`: pack, level number, picture name, then the difficulty acorns once the board is ready.
private struct SplashTitle: View {
    @ObservedObject var model: GameModel

    var body: some View {
        VStack(spacing: 2) {
            if !model.packLabel.isEmpty {
                Text(model.packLabel.uppercased())
                    .font(Theme.body(13, 800))
                    .tracking(13 * 0.06)
                    .foregroundStyle(Color(red: 31 / 255, green: 42 / 255, blue: 24 / 255, opacity: 0.6))
                    .cssLine(Theme.uiBody(13, 800), 13 * 1.45 - 2.0 / 3)
            }
            Text(model.subtitle)
                .font(Theme.display(52))
                .tracking(52 * 0.01)
                .foregroundStyle(Color(hex: 0x1F2A18))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .cssLine(Theme.uiDisplay(52), 52 - 2.0 / 3)
            if model.mode == .daily {
                // The daily puzzle: "Current Streak" over the streak itself, both big.
                Text(model.title)
                    .font(Theme.display(52))
                    .foregroundStyle(Color(hex: 0x1F2A18))
                    .lineLimit(1)
                    .cssLine(Theme.uiDisplay(52), 52 - 2.0 / 3)
            } else {
                Text(model.title)
                    .font(Theme.body(20, 800))
                    .foregroundStyle(Color(hex: 0x3A4A30))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
                .cssLine(Theme.uiBody(20, 800), 24)
            let n = model.introReady ? model.tier : nil
            Text(n.map { String(repeating: "🌰", count: $0) } ?? " ")
                .font(.system(size: 30))
                .tracking(2)
                .frame(minHeight: 34)
                .opacity(n == nil ? 0 : 1)
                .scaleEffect(n == nil ? 0.6 : 1)
                .animation(.interpolatingSpring(stiffness: 260, damping: 14), value: n)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }
}

/// The SceneKit view, driven frame by frame like the page's requestAnimationFrame loop.
struct SceneCanvas: UIViewRepresentable {
    let run: GameModel.SceneRun
    let size: CGSize
    let ready: () -> Bool
    /// When set, the scene ends only once this says so (the intro's Start button), not on its own or on a tap.
    var go: (() -> Bool)? = nil
    let done: () -> Void

    // Built once and reused, like the page's win3d / chip3d.
    @MainActor static let kiss = KissScene()
    @MainActor static let chips = ChipScene()

    func makeCoordinator() -> Player { Player() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: CGRect(origin: .zero, size: size))
        v.backgroundColor = .clear
        v.isOpaque = false
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = true
        v.preferredFramesPerSecond = 60
        v.isUserInteractionEnabled = true
        let p = context.coordinator
        p.view = v
        let tap = UILongPressGestureRecognizer(target: p, action: #selector(Player.pressed(_:)))
        tap.minimumPressDuration = 0
        v.addGestureRecognizer(tap)
        p.go = go
        p.start(run, ready: ready, done: done)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        context.coordinator.ready = ready
        context.coordinator.go = go
        context.coordinator.resize(size)
    }

    static func dismantleUIView(_ v: SCNView, coordinator: Player) { coordinator.stop() }

    @MainActor
    final class Player: NSObject {
        weak var view: SCNView?
        var ready: () -> Bool = { true }
        var go: (() -> Bool)?
        private var done: () -> Void = {}
        private var run: GameModel.SceneRun?
        private var link: CADisplayLink?
        private var t0: CFTimeInterval = 0
        private var skip = false
        private var finished = false

        func start(_ r: GameModel.SceneRun, ready: @escaping () -> Bool, done: @escaping () -> Void) {
            run = r
            self.ready = ready
            self.done = done
            switch r.kind {
            case .win:
                view?.scene = SceneCanvas.kiss.scene
                view?.pointOfView = SceneCanvas.kiss.camera
            case .intro, .lose:
                view?.scene = SceneCanvas.chips.scene
                view?.pointOfView = SceneCanvas.chips.camera
            }
            t0 = CACurrentMediaTime()
            step()
            let l = CADisplayLink(target: self, selector: #selector(tick))
            l.add(to: .main, forMode: .common)
            link = l
        }

        func resize(_ s: CGSize) {
            guard let r = run, s.height > 0 else { return }
            r.kind == .win ? SceneCanvas.kiss.resize(s.width, s.height) : SceneCanvas.chips.resize(s.width, s.height)
        }

        func stop() {
            link?.invalidate()
            link = nil
        }

        @objc func pressed(_ g: UIGestureRecognizer) {
            // pointerdown: skip (the intro only once the board is ready)
            if g.state == .began, go == nil, ready() { skip = true }
        }

        @objc private func tick() { step() }

        private func step() {
            guard let r = run, !finished else { return }
            var t = Float(CACurrentMediaTime() - t0)
            #if DEBUG
            // `-sceneT 2.6` holds the scene at that moment.
            if let f = UserDefaults.standard.string(forKey: "sceneT"), let v = Float(f) { t = v; skip = false }
            #endif
            let end: Float
            switch r.kind {
            case .win:
                end = KissScene.end
                SceneCanvas.kiss.setTime(min(end, t))
            case .intro:
                end = ChipScene.introEnd
                SceneCanvas.chips.setTime(.intro, t)
            case .lose:
                end = ChipScene.loseEnd
                SceneCanvas.chips.setTime(.lose, t)
            }
            let over = go.map { $0() } ?? (t >= end || skip)
            if over && ready() {
                finished = true
                done()
                // keep drawing the final pose while the layer fades
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.stop() }
            }
        }
    }
}

// MARK: - Cards (.overlay)

/// The page's `.overlay` card over the stage: win or stuck.
struct ResultCard: View {
    @ObservedObject var model: GameModel

    var body: some View {
        VStack(spacing: 12) {
            switch model.status {
            case .won: winCard
            case .stuck: stuckCard
            case .failed(let message):
                P(message)
                Row { Big("Next level") { model.next() } }
            default: EmptyView()
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 238 / 255, green: 244 / 255, blue: 232 / 255, opacity: 0.93).ignoresSafeArea())
        .contentShape(Rectangle())
    }

    @ViewBuilder private var winCard: some View {
        let w = model.lastWin
        if model.mode == .daily {
            H2("Day \(model.daily.count) cleared")
            Text("🔥 \(model.daily.streak)")
                .font(Theme.body(30, 900))
                .foregroundStyle(Color(hex: 0xC2410C))
                .accessibilityLabel("Streak: \(model.daily.streak) days")
        } else {
            H2(model.mode == .mining ? "Challenge cleared" : "Board cleared")
        }
        HStack(spacing: 8) {
            CoinIcon().frame(width: 30, height: 30)
            Text("+\((w.base + w.bonus).formatted())")
                .font(Theme.display(34))
                .foregroundStyle(Theme.ink)
                .cssLine(Theme.uiDisplay(34), 34 * 1.45)
        }
        HStack(spacing: 6) {
            BlockIcon(size: 14)
            // .lifeline is a flex row: the count and the words are separate items 6 apart
            Text(short3(model.lifetime)).font(Theme.body(13, 800))
            Text("blocks cleared, all time").font(Theme.body(13, 500))
                .cssLine(Theme.uiBody(13, 500), 13 * 1.45 - 1)
        }
        .foregroundStyle(Color(hex: 0x4A5841))
        .padding(.top, 2 - 3)        // measured against the web layout
        switch model.mode {
        case .mining:
            Note("\(model.paraRound) Coin Mining challenge\(model.paraRound == 1 ? "" : "s") cleared")
            Row {
                Big("Next challenge") { model.next() }
                Big("Home", alt: true) { withAnimation(.easeOut(duration: 0.2)) { model.goHome() } }
            }
        case .daily:
            Note("Come back tomorrow to keep your streak.")
            Row { Big("Home") { withAnimation(.easeOut(duration: 0.2)) { model.goHome() } } }
        case .level:
            levelWinExtras
        }
    }

    @ViewBuilder private var levelWinExtras: some View {
        let w = model.lastWin
        if w.bonus > 0 {
            Text("First-try bonus +\(w.bonus)")
                .font(Theme.body(13, 800))
                .foregroundStyle(Color(hex: 0x8A6500))
                .cssLine(Theme.uiBody(13, 800), 13 * 1.45)
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .background(Color(hex: 0xFFF3C4), in: Capsule())
        }
        if let pick = model.tailorPick {
            VStack(spacing: 6) {
                Text("Next time:")
                    .font(Theme.body(13, 800))
                    .foregroundStyle(Theme.ink)
                    .cssLine(Theme.uiBody(13, 800), 13 * 1.45)
                HStack(spacing: 6) {
                    TailorButton(title: "A little easier", on: pick == .easier) { model.pickTailor(.easier) }
                    TailorButton(title: "About the same", on: pick == .same) { model.pickTailor(.same) }
                    TailorButton(title: "A little harder", on: pick == .harder) { model.pickTailor(.harder) }
                }
                Note(pick == .tiny ? "First-try win, so next time is a tiny bit harder." : "")
            }
            .padding(.top, 2)
            .padding(.bottom, 4)
        }
        Row {
            Big("Next level") { model.next() }
            Big("Home", alt: true) { withAnimation(.easeOut(duration: 0.2)) { model.goHome() } }
        }
    }

    @ViewBuilder private var stuckCard: some View {
        let slots = model.level?.slots ?? 5
        let paradise = model.level?.diff == "paradise"
        H2("Chipmunks stuck")
        P("All \(slots) slots are holding chipmunks that cannot reach their color.")
        if paradise {
            Note("No hearts lost in Coin Mining. Try again!")
        } else {
            if model.mode == .daily { Note("No hearts lost on the daily puzzle.") }
            let can = model.coins >= GameModel.continuePrice
            Row {
                Button { model.continueGame() } label: {
                    HStack(spacing: 0) {
                        Text("Continue ")
                        CoinIcon().frame(width: 18, height: 18).padding(.leading, 8).padding(.trailing, 4).offset(y: 1)
                        Text("\(GameModel.continuePrice)")
                    }
                    .bigLabel(alt: false)
                }
                .buttonStyle(Pressable())
                .disabled(!can)
                .opacity(can ? 1 : 0.45)
            }
            Text("Clears 3 slots and their blocks" + (can ? "" : " · you need \((GameModel.continuePrice - model.coins).formatted()) more coins"))
                .font(Theme.body(13, 800))
                .foregroundStyle(Color(hex: 0x4A5841))
                .cssLine(Theme.uiBody(13, 800), 13 * 1.45 - 1)
        }
        if model.easeNext {
            Note("Three tries without a win, so your next try gets a new board that's a little easier.")
        }
        Row {
            Big("Undo last tap") { model.undo() }
            Big("Restart", alt: true) { model.retry() }
        }
    }
}

/// `.overlay h2`: Lilita One 38, line-height 1.45.
private struct H2: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text)
            .font(Theme.display(38))
            .tracking(38 * 0.01)
            .foregroundStyle(Theme.ink)
            .cssLine(Theme.uiDisplay(38), 38 * 1.45 - 4.0 / 3)   // measured against the web layout
    }
}

/// `.overlay p`: body text, at most 28 characters wide.
private struct P: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        let f = Theme.uiBody(15, 500)
        let ch = ("0" as NSString).size(withAttributes: [.font: f]).width
        Text(text)
            .font(Theme.body(15, 500))
            .foregroundStyle(Color(hex: 0x4A5841))
            .cssLine(f, 15 * 1.45)
            .frame(maxWidth: 28 * ch)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// `.tailor-note`.
private struct Note: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(Theme.body(12, 500))
                .foregroundStyle(Color(hex: 0x6B5A3A))
                .cssLine(Theme.uiBody(12, 500), 12 * 1.45)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// `.row`: buttons 8 apart, wrapping.
private struct Row<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content }
            VStack(spacing: 8) { content }
        }
    }
}

/// `.big` (and `.big.alt`).
private struct Big: View {
    let title: String
    var alt = false
    let action: () -> Void
    init(_ t: String, alt: Bool = false, action: @escaping () -> Void) {
        title = t
        self.alt = alt
        self.action = action
    }
    var body: some View {
        Button(action: action) { Text(title).bigLabel(alt: alt) }
            .buttonStyle(Pressable())
    }
}

extension View {
    func bigLabel(alt: Bool) -> some View {
        self.font(Theme.body(16, 800))
            .foregroundStyle(alt ? Theme.ink : Theme.card)
            .cssLine(Theme.uiBody(16, 800), 16 * 1.45)
            .lineLimit(1)
            .padding(.vertical, 12)
            .padding(.horizontal, 22)
            .background(alt ? Theme.button : Theme.ink, in: RoundedRectangle(cornerRadius: 16, style: .circular))
    }
}

/// `.tl`: the win card's difficulty pills.
private struct TailorButton: View {
    let title: String
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(13, 800))
                .foregroundStyle(on ? .white : Theme.ink)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(on ? Color(hex: 0x2E7D32) : .white, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Color(hex: 0x2E7D32) : Color(hex: 0xC9B48A), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

/// `.blk`: a small orange block.
struct BlockIcon: View {
    let size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .circular)
            .fill(Color(hex: 0xFB8C00))
            .overlay(alignment: .bottom) {
                Rectangle().fill(.black.opacity(0.28)).frame(height: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .circular))
            .frame(width: size, height: size)
    }
}

/// JS short3: three significant digits (987, 1.36k, 12.8k, 198k, 1.23M).
func short3(_ n: Int) -> String {
    if n < 1000 { return String(n) }
    let U = ["k", "M", "B", "T"]
    var v = Double(n), i = -1
    func p3(_ x: Double) -> Double { Double(String(format: "%.3g", x)) ?? x }
    repeat {
        v /= 1000
        i += 1
    } while p3(v) >= 1000 && i < U.count - 1
    let d = v >= 99.95 ? 0 : v >= 9.995 ? 1 : 2
    return String(format: "%.\(d)f", p3(v)) + U[i]
}

extension View {
    /// CSS line-height: pads the text so its line box is `lh` points tall, as the page lays it out.
    func cssLine(_ font: UIFont, _ lh: CGFloat) -> some View {
        padding(.vertical, (lh - font.lineHeight) / 2)
    }
}
