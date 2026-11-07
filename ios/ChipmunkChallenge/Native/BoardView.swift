import ChipmunkEngine
import QuartzCore
import SwiftUI
import UIKit

/* The board canvas, ported from the web page's canvas code (makeSprite, paintOff, paintCell, repaintAround, hole,
   drawCritter, drawFrame). Function for function and number for number, so it draws the same picture.

   Two layers, as on the page: a cached "offscreen" image of the tray and blocks (redrawn only around a block that
   leaves), and a live layer redrawn every frame with the drain and the critters. */

/// The view SwiftUI places; it owns the display link that drives the game clock.
struct BoardCanvas: UIViewRepresentable {
    let model: GameModel

    func makeUIView(context: Context) -> BoardView { BoardView(model: model) }
    func updateUIView(_ view: BoardView, context: Context) {}
}

final class BoardView: UIView {
    let model: GameModel
    private let offLayer = CALayer()
    private let live: LiveView
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval?

    // Board state (JS: lv, cs, the offscreen canvas).
    private var builtVersion = -1
    private var cs: CGFloat = 0
    private var scale: CGFloat = 3
    private var off: CGContext?
    private var offDirty = false
    private var shown: [UInt8] = []
    fileprivate var sprites = SpriteCache()

    init(model: GameModel) {
        self.model = model
        live = LiveView()
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        layer.addSublayer(offLayer)
        offLayer.contentsGravity = .resize
        live.board = self
        addSubview(live)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        live.frame = bounds
        offLayer.frame = bounds
    }

    // MARK: - Frame loop (JS: the animation loop calling drawFrame)

    @objc private func tick(_ l: CADisplayLink) {
        let dt = lastTime.map { l.timestamp - $0 } ?? 0
        lastTime = l.timestamp
        guard let lv = model.level else { return }
        if builtVersion != model.boardVersion || cs != model.cellSize { sizeBoard(lv) }
        model.advance(by: dt)
        guard let m = model.sim else { return }
        // A block left: repaint around it (JS CB.arrive → repaintAround). A chipmunk standing at its block for the
        // pickup pause still shows the block; it goes once the chipmunk lifts it.
        var holding = Set<Int>()
        for a in m.ants where a.hold > 0 && model.simT < a.ta + a.hold { holding.insert(a.i) }
        for i in 0..<min(shown.count, m.s.b.count) where shown[i] != m.s.b[i] && !holding.contains(i) {
            shown[i] = m.s.b[i]
            repaintAround(lv, m.s.b, i)
        }
        if offDirty, let img = off?.makeImage() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            offLayer.contents = img
            CATransaction.commit()
            offDirty = false
        }
        live.setNeedsDisplay()
    }

    // MARK: - Size (JS sizeBoard)

    /// The board's cell size for a given width: whole device pixels, like the page.
    static func cellSize(width avail: CGFloat, NW: Int, scale: CGFloat) -> CGFloat {
        max(4, (avail / CGFloat(NW) * scale).rounded(.down) / scale)
    }

    private func sizeBoard(_ lv: Level) {
        builtVersion = model.boardVersion
        scale = window?.screen.scale ?? 3
        cs = model.cellSize
        let W = CGFloat(lv.NW) * cs, H = CGFloat(lv.NH) * cs
        let pw = Int((W * scale).rounded()), ph = Int((H * scale).rounded())
        guard pw > 0, ph > 0,
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        // Point units, y down (like a canvas with setTransform(dpr,...)).
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: scale, y: -scale)
        off = ctx
        sprites = SpriteCache(cs: cs, scale: scale, chars: lv.art.chars)
        live.cs = cs
        shown = model.sim?.s.b ?? lv.art.cells
        paintOff(lv)
    }

    // MARK: - Offscreen board (JS paintOff, paintCell, repaintAround)

    private func withOff(_ body: (CGContext) -> Void) {
        guard let off else { return }
        UIGraphicsPushContext(off)
        body(off)
        UIGraphicsPopContext()
        offDirty = true
    }

    private func paintOff(_ lv: Level) {
        let W = CGFloat(lv.NW) * cs, trayH = CGFloat(MG.t + lv.H + 1) * cs
        let b = shown
        withOff { g in
            g.clear(CGRect(x: 0, y: 0, width: W, height: CGFloat(lv.NH) * cs))
            g.saveGState()
            // Shadow offsets are in device space (y up here), so "down" is negative.
            g.setShadow(offset: CGSize(width: 0, height: -cs * 0.35 * scale), blur: cs * 1.4 * scale,
                        color: UIColor(white: 0, alpha: 0.22).cgColor)
            g.setFillColor(UIColor(hex: Theme.walk).cgColor)
            g.addPath(UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: W, height: trayH), cornerRadius: cs * 1.3).cgPath)
            g.fillPath()
            g.restoreGState()
            g.setFillColor(UIColor(hex: Theme.trayIn).cgColor)
            g.fill(CGRect(x: CGFloat(MG.l) * cs, y: CGFloat(MG.t) * cs, width: CGFloat(lv.W) * cs, height: CGFloat(lv.H) * cs))
            for i in b.indices where b[i] != 0 { paintCell(g, lv, b, i) }
        }
    }

    private func paintCell(_ g: CGContext, _ lv: Level, _ b: [UInt8], _ i: Int) {
        let n = lv.boardToNav(i)
        let x = CGFloat(n % lv.NW) * cs, y = CGFloat(n / lv.NW) * cs
        g.setFillColor(UIColor(hex: Theme.trayIn).cgColor)
        g.fill(CGRect(x: x, y: y, width: cs, height: cs))
        let v = b[i], r = i / lv.W
        if v != 0 {
            sprites.block(g, x, y, cs, v, r < lv.H - 1 && b[i + lv.W] > 0, cornerMask(lv, b, i))
        } else if r > 0 && b[i - lv.W] != 0 {
            sprites.block(g, x, y - cs, cs, b[i - lv.W], false, cornerMask(lv, b, i - lv.W))
        }
    }

    private func cornerMask(_ lv: Level, _ b: [UInt8], _ i: Int) -> Int {
        let W = lv.W, r = i / W, c = i % W
        func o(_ rr: Int, _ cc: Int) -> Bool { rr < 0 || cc < 0 || rr >= lv.H || cc >= W || b[rr * W + cc] == 0 }
        let T = o(r - 1, c), B = o(r + 1, c), L = o(r, c - 1), R = o(r, c + 1)
        return (T && L ? 1 : 0) | (T && R ? 2 : 0) | (B && L ? 4 : 0) | (B && R ? 8 : 0)
    }

    /// After a block leaves, its neighbours' corners may open: repaint the 3x3 around it, top row first, plus the
    /// cells under the side neighbours that their hanging side bands cover.
    private func repaintAround(_ lv: Level, _ b: [UInt8], _ i: Int) {
        let W = lv.W, r = i / W, c = i % W
        withOff { g in
            for rr in (r - 1)...(r + 2) {
                for cc in (c - 1)...(c + 1) {
                    if rr < 0 || cc < 0 || cc >= W { continue }
                    if rr >= lv.H {
                        if rr == lv.H {
                            let j = (lv.H - 1) * W + cc
                            paintBelowEdge(g, lv, j)
                            if b[j] != 0 { paintCell(g, lv, b, j) }
                        }
                        continue
                    }
                    paintCell(g, lv, b, rr * W + cc)
                }
            }
        }
    }

    /// Bottom row: clear the band hanging into the tray margin.
    private func paintBelowEdge(_ g: CGContext, _ lv: Level, _ i: Int) {
        let n = lv.boardToNav(i)
        let x = CGFloat(n % lv.NW) * cs, y = CGFloat(n / lv.NW) * cs + cs
        g.setFillColor(UIColor(hex: Theme.walk).cgColor)
        g.fill(CGRect(x: x, y: y, width: cs, height: cs * SpriteCache.depth + 1))
    }

    // MARK: - Touch: nothing on the board itself is tappable (the tools work from the tray, lanes and slots).
}

// MARK: - The live layer: drain and critters (JS drawFrame)

private final class LiveView: UIView {
    weak var board: BoardView?
    var cs: CGFloat = 0
    private var tones: [Int: Tone] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let board, let lv = board.model.level, let m = board.model.sim, cs > 0,
              let g = UIGraphicsGetCurrentContext() else { return }
        let NW = lv.NW
        hole(g, (CGFloat(lv.drain % NW) + 0.5) * cs, (CGFloat(lv.drain / NW) + 0.5) * cs, cs * 2.4)
        let now = CACurrentMediaTime() * 1000
        let simT = board.model.simT
        for a in m.ants {
            // During the pickup pause it stands at the block, still facing it, cheeks not yet full.
            let standing = a.picked && simT < a.ta + a.hold
            var out = a
            out.picked = false
            let p = standing ? antPose(lv, out, at: a.ta - 0.001) : antPose(lv, a, at: simT)
            let carry = a.picked && !standing
            drawCritter(g, lv, CGFloat(p.x) * cs, CGFloat(p.y) * cs, CGFloat(p.dx), CGFloat(p.dy),
                        carry ? a.c : 0, now, a.c)
        }
        drawAcorns(g, lv, CACurrentMediaTime())
    }

    /// Acorn Drop: each acorn falls 160 points onto its cell, turning upright, then pops (JS .acorn-fall).
    private func drawAcorns(_ g: CGContext, _ lv: Level, _ now: CFTimeInterval) {
        guard let falls = board?.model.acornFalls, !falls.isEmpty else { return }
        let font = UIFont.systemFont(ofSize: 18)
        let glyph = NSAttributedString(string: "🌰", attributes: [.font: font])
        let gs = glyph.size()
        for f in falls {
            let t = now - f.start
            if t < 0 { continue }
            let n = lv.boardToNav(f.cell)
            let x = (CGFloat(n % lv.NW) + 0.5) * cs, y = (CGFloat(n / lv.NW) + 0.5) * cs
            var dy: CGFloat = 0, rot: CGFloat = 0, scale: CGFloat = 1, alpha: CGFloat = 1
            if t < GameModel.acornFall {
                let u = CGFloat(t / GameModel.acornFall), e = u * u
                dy = -160 * (1 - e)
                rot = -40 * (1 - e) * .pi / 180
                alpha = min(1, u / 0.25)
            } else {
                let u = CGFloat(min(1, (t - GameModel.acornFall) / 0.3))
                scale = 1 + 0.6 * u
                alpha = 1 - u
            }
            if alpha <= 0 { continue }
            g.saveGState()
            g.setAlpha(alpha)
            g.translateBy(x: x, y: y + dy)
            g.rotate(by: rot)
            g.scaleBy(x: scale, y: scale)
            UIGraphicsPushContext(g)
            glyph.draw(at: CGPoint(x: -gs.width / 2, y: -gs.height / 2))
            UIGraphicsPopContext()
            g.restoreGState()
        }
    }

    private func tone(_ lv: Level, _ col: Int) -> Tone {
        if let t = tones[col] { return t }
        let t = Tone(lv.rgb(col))
        tones[col] = t
        return t
    }

    /// The drain: a soft dark hole in the apron.
    private func hole(_ g: CGContext, _ x: CGFloat, _ y: CGFloat, _ rad: CGFloat) {
        let colors = [UIColor(hex: 0x2A1408), UIColor(hex: 0x6B3A1D), UIColor(hex: 0x6B3A1D, alpha: 0.55),
                      UIColor(hex: 0x6B3A1D, alpha: 0)].map(\.cgColor) as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors,
                              locations: [0, 0.62, 0.86, 1])!
        g.saveGState()
        g.addEllipse(in: CGRect(x: x - rad, y: y - rad * 0.7, width: rad * 2, height: rad * 1.4))
        g.clip()
        g.drawRadialGradient(grad, startCenter: CGPoint(x: x, y: y - rad * 0.12), startRadius: rad * 0.15,
                             endCenter: CGPoint(x: x, y: y), endRadius: rad,
                             options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        g.restoreGState()
    }

    /// A chipmunk seen from above, tinted its nest's color (JS drawCritter, crew = chipmunks).
    private func drawCritter(_ g: CGContext, _ lv: Level, _ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ dy: CGFloat,
                             _ carry: Int, _ t: Double, _ col: Int) {
        let s = cs * CGFloat(SIM.BODY) / 1.35 * 1.25          // chipmunks drawn 25% bigger
        let tn = tone(lv, col)
        let ang = atan2(dy, dx)
        let ink = UIColor(red: 20 / 255, green: 12 / 255, blue: 6 / 255, alpha: 0.8)
        let step = CGFloat(sin(t / 26))
        let lw = max(0.6, s * 0.06)

        func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
            g.addEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        }
        func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) { ellipse(cx, cy, r, r) }
        func fillStroke(_ fill: UIColor) {
            g.setFillColor(fill.cgColor)
            g.drawPath(using: .fillStroke)
        }
        func fill(_ c: UIColor) {
            g.setFillColor(c.cgColor)
            g.fillPath()
        }

        g.saveGState()
        g.translateBy(x: x, y: y)
        g.rotate(by: ang + 0.13 * CGFloat(sin(t / 38 + Double(col))))
        g.setLineWidth(lw)
        g.setStrokeColor(ink.cgColor)

        // Paws: four small ovals that trot (front and back pairs swap).
        for (px, py, ph) in [(0.2, 0.2, 1.0), (0.2, -0.2, -1.0), (-0.2, 0.24, -1.0), (-0.2, -0.24, 1.0)] as [(CGFloat, CGFloat, CGFloat)] {
            ellipse((px + 0.06 * step * ph) * s, py * s, s * 0.09, s * 0.06)
            fillStroke(tn.lo)
        }
        // Tail: a slim chain of puffs that flicks from side to side and snaps there.
        let n = 9
        let flick = CGFloat(tanh(3.5 * sin(t / 150 + Double(col) * 2)))
        func tp(_ f: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
            (-(0.3 + 0.4 * f) * s, (0.2 * sin(f * .pi * 0.6) * flick) * s, (0.06 + 0.025 * f) * s)
        }
        for i in stride(from: n - 1, through: 0, by: -1) {
            let (tx, ty, rad) = tp(CGFloat(i) / CGFloat(n - 1))
            circle(tx, ty, rad)
            fillStroke(tn.face)
        }
        for i in stride(from: n - 1, through: 0, by: -1) {
            let f = CGFloat(i) / CGFloat(n - 1)
            let (tx, ty, rad) = tp(f)
            circle(tx, ty, rad * 0.7)
            fill(f > 0.55 ? tn.hi : tn.face)
        }
        // Body, with the dark-and-light back stripes.
        ellipse(-0.04 * s, 0, 0.31 * s, 0.27 * s)
        fillStroke(tn.face)
        g.setLineCap(.round)
        for (o, c2, w2) in [(0, ink, 0.075), (-0.12, tn.gloss, 0.05), (0.12, tn.gloss, 0.05), (-0.2, ink, 0.04), (0.2, ink, 0.04)] as [(CGFloat, UIColor, CGFloat)] {
            g.setStrokeColor(c2.cgColor)
            g.setLineWidth(w2 * s)
            g.move(to: CGPoint(x: -0.28 * s, y: o * s * 0.8))
            g.addLine(to: CGPoint(x: 0.14 * s, y: o * s * 0.7))
            g.strokePath()
        }
        g.setLineCap(.butt)
        g.setStrokeColor(ink.cgColor)
        g.setLineWidth(lw)
        // Ears.
        for sg in [1.0, -1.0] as [CGFloat] {
            ellipse(0.27 * s, sg * 0.17 * s, 0.085 * s, 0.095 * s)
            fillStroke(tn.face)
            ellipse(0.28 * s, sg * 0.17 * s, 0.04 * s, 0.05 * s)
            fill(tn.hi)
        }
        // Cheeks puff out while it carries a block.
        if carry != 0 {
            for sg in [1.0, -1.0] as [CGFloat] {
                circle(0.4 * s, sg * 0.17 * s, 0.11 * s)
                fillStroke(tn.face)
                circle(0.42 * s, sg * 0.19 * s, 0.05 * s)
                fill(tn.gloss)
            }
        }
        // Head, muzzle, eyes and nose.
        ellipse(0.36 * s, 0, 0.21 * s, 0.19 * s)
        fillStroke(tn.face)
        ellipse(0.45 * s, 0, 0.09 * s, 0.11 * s)
        fill(tn.gloss)
        for sg in [1.0, -1.0] as [CGFloat] {
            circle(0.44 * s, sg * 0.085 * s, 0.042 * s)
            fill(ink)
        }
        circle(0.56 * s, 0, 0.04 * s)
        fill(ink)
        for sg in [1.0, -1.0] as [CGFloat] {
            circle(0.455 * s, sg * 0.085 * s - 0.015 * s, 0.015 * s)
            fill(UIColor(white: 1, alpha: 0.9))
        }
        if carry != 0, let board {
            g.rotate(by: -ang)
            let hx = cos(ang) * s * 0.8, hy = sin(ang) * s * 0.8
            board.sprites.block(g, (hx - cs * 0.5).rounded(), (hy - cs * 0.5).rounded(), cs, UInt8(carry), false, 15)
        }
        g.restoreGState()
    }
}

// MARK: - Block sprites (JS makeSprite / sprite / block)

/// Each color's block drawn once per board size: a cube seen from slightly above, with a flat saturated top face,
/// a darker side band along the bottom edge (only where the bottom is exposed), a light rim and a highlight streak.
struct SpriteCache {
    static let depth: CGFloat = 0.42                       // DEPTH
    private(set) var S = 0
    private(set) var D = 0
    private var chars: [Character] = []
    private var cache: [Int: UIImage] = [:]
    /// Washed-out grey instead of the real colors (the daily card's mystery thumbnail).
    private var grey = false

    init() {}

    init(cs: CGFloat, scale: CGFloat, chars: [Character], grey: Bool = false) {
        S = max(4, Int(JSRound(Double(cs * scale))))
        D = max(2, Int(JSRound(Double(S) * Double(Self.depth))))
        self.chars = chars
        self.grey = grey
    }

    private func hex(_ col: UInt8) -> UInt32 {
        let h = col == ROCK ? Theme.rock : (Int(col) <= chars.count ? PALETTE[chars[Int(col) - 1]] ?? 0x888888 : 0x888888)
        guard grey else { return h }
        let y = (0.3 * Double(h >> 16) + 0.59 * Double((h >> 8) & 255) + 0.11 * Double(h & 255)) * 0.35 + 150
        let v = UInt32(y.rounded())
        return v << 16 | min(255, v + 4) << 8 | (v - 2)
    }

    /// JS block(g, x, y, s, col, flat, mask).
    mutating func block(_ g: CGContext, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ col: UInt8, _ flat: Bool, _ mask0: Int) {
        guard S > 0 else { return }
        let mask = flat ? mask0 & 3 : mask0
        let img = sprite(col, flat, mask)
        UIGraphicsPushContext(g)
        img.draw(in: CGRect(x: x, y: y, width: s, height: flat ? s : s * (1 + Self.depth)))
        UIGraphicsPopContext()
    }

    private mutating func sprite(_ col: UInt8, _ flat: Bool, _ mask: Int) -> UIImage {
        let k = Int(col) * 64 + (flat ? 32 : 0) + mask
        if let c = cache[k] { return c }
        let c = makeSprite(col, flat, mask)
        cache[k] = c
        return c
    }

    private func makeSprite(_ col: UInt8, _ flat: Bool, _ mask: Int) -> UIImage {
        let S = CGFloat(self.S), D = flat ? 0 : CGFloat(self.D)
        let rock = col == ROCK, h = hex(col)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: S, height: S + D), format: fmt).image { ctx in
            let g = ctx.cgContext
            let R = S * 0.24, H = S + D
            func r(_ k: Int) -> CGFloat { mask & k != 0 ? R : 0 }
            func linear(_ rect: CGRect, _ y0: CGFloat, _ y1: CGFloat, _ stops: [(CGFloat, UIColor)]) {
                g.saveGState()
                g.clip(to: rect)
                let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                      colors: stops.map(\.1.cgColor) as CFArray, locations: stops.map(\.0))!
                g.drawLinearGradient(grad, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1),
                                     options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                g.restoreGState()
            }
            func radial(_ rect: CGRect, _ cx: CGFloat, _ cy: CGFloat, _ rad: CGFloat, _ c0: UIColor) {
                g.saveGState()
                g.clip(to: rect)
                let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                      colors: [c0.cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray,
                                      locations: [0, 1])!
                g.drawRadialGradient(grad, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                     endCenter: CGPoint(x: cx, y: cy), endRadius: rad, options: [.drawsAfterEndLocation])
                g.restoreGState()
            }
            func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ hh: CGFloat, _ rad: CGFloat) {
                g.addPath(UIBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: hh), cornerRadius: rad).cgPath)
            }

            // Outline: only corners open on both sides are cut round.
            let path = CGMutablePath()
            path.move(to: CGPoint(x: r(1), y: 0))
            path.addLine(to: CGPoint(x: S - r(2), y: 0))
            if r(2) > 0 { path.addArc(tangent1End: CGPoint(x: S, y: 0), tangent2End: CGPoint(x: S, y: r(2)), radius: r(2)) }
            path.addLine(to: CGPoint(x: S, y: H - r(8)))
            if r(8) > 0 { path.addArc(tangent1End: CGPoint(x: S, y: H), tangent2End: CGPoint(x: S - r(8), y: H), radius: r(8)) }
            path.addLine(to: CGPoint(x: r(4), y: H))
            if r(4) > 0 { path.addArc(tangent1End: CGPoint(x: 0, y: H), tangent2End: CGPoint(x: 0, y: H - r(4)), radius: r(4)) }
            path.addLine(to: CGPoint(x: 0, y: r(1)))
            if r(1) > 0 { path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: r(1), y: 0), radius: r(1)) }
            path.closeSubpath()
            g.addPath(path)
            g.clip()

            if D > 0 {
                linear(CGRect(x: 0, y: S, width: S, height: D), S, H, [(0, mix(h, 0, 0.34)), (1, mix(h, 0, 0.55))])
                let sw = max(1, S * 0.035)
                g.setFillColor(UIColor(white: 0, alpha: 0.18).cgColor)
                if mask & 4 == 0 { g.fill(CGRect(x: 0, y: S, width: sw, height: D)) }
                if mask & 8 == 0 { g.fill(CGRect(x: S - sw, y: S, width: sw, height: D)) }
                for (k, x) in [(4, CGFloat(0)), (8, S)] where mask & k == 0 {
                    radial(CGRect(x: x > 0 ? S * 0.6 : 0, y: S, width: S * 0.4, height: D), x, H, S * 0.3,
                           UIColor(white: 0, alpha: 0.22))
                }
                if mask & 12 != 0 {
                    g.setFillColor(UIColor(white: 0, alpha: 0.12).cgColor)
                    g.fill(CGRect(x: 0, y: H - max(1, S * 0.05), width: S, height: max(1, S * 0.05)))
                }
            }
            linear(CGRect(x: 0, y: 0, width: S, height: S), 0, S,
                   [(0, mix(h, 0xFFFFFF, 0.1)), (0.3, UIColor(hex: h)), (1, mix(h, 0, 0.05))])
            // Soft corner shading on the face: light at the top corners, shadow at the bottom ones.
            func corner(_ x: CGFloat, _ y: CGFloat, _ a: CGFloat, _ k: Int) {
                if mask & k != 0 && (k < 4 || flat) { return }
                radial(CGRect(x: x > 0 ? S * 0.5 : 0, y: y > 0 ? S * 0.5 : 0, width: S * 0.5, height: S * 0.5),
                       x, y, S * 0.34, UIColor(white: 0, alpha: a))
            }
            corner(0, 0, 0.10, 1)
            corner(S, 0, 0.12, 2)
            corner(0, S, 0.14, 4)
            corner(S, S, 0.17, 8)
            if mask & 3 != 0 {
                linear(CGRect(x: 0, y: 0, width: S, height: S * 0.25), 0, S * 0.25,
                       [(0, UIColor(white: 1, alpha: 0.18)), (1, UIColor(white: 1, alpha: 0))])
            }
            g.setFillColor(mix(h, 0xFFFFFF, 0.28).cgColor)
            rr(S * 0.12 + (mask & 1 != 0 ? S * 0.06 : 0), S * 0.04,
               S * 0.76 - (mask & 1 != 0 ? S * 0.06 : 0) - (mask & 2 != 0 ? S * 0.06 : 0), max(1, S * 0.07), S * 0.035)
            g.fillPath()
            g.setFillColor(UIColor(white: 1, alpha: 0.34).cgColor)
            rr(S * 0.56, S * 0.62, S * 0.24, max(1, S * 0.075), S * 0.04)
            g.fillPath()
            let lw = max(1, S * 0.035)
            g.setStrokeColor(UIColor(white: 0, alpha: 0.12).cgColor)
            g.setLineWidth(lw)
            if mask == 0 {
                g.stroke(CGRect(x: lw / 2, y: lw / 2, width: S - lw, height: S - lw))
            } else {
                let w = lw / 2
                g.move(to: CGPoint(x: w, y: S - w))
                g.addLine(to: CGPoint(x: w, y: w))
                g.addLine(to: CGPoint(x: S - w, y: w))
                g.addLine(to: CGPoint(x: S - w, y: S - w))
                g.addLine(to: CGPoint(x: w, y: S - w))
                g.strokePath()
            }
            if D > 0 {
                g.setFillColor(UIColor(white: 0, alpha: 0.22).cgColor)
                g.fill(CGRect(x: 0, y: S - max(1, S * 0.04), width: S, height: max(1, S * 0.04)))
            }
            if rock {
                // Stone: darker specks and a hairline crack.
                g.setFillColor(UIColor(red: 40 / 255, green: 34 / 255, blue: 28 / 255, alpha: 0.35).cgColor)
                for (x, y, rad) in [(0.28, 0.3, 0.09), (0.68, 0.22, 0.06), (0.6, 0.66, 0.1), (0.24, 0.72, 0.06)] as [(CGFloat, CGFloat, CGFloat)] {
                    g.addArc(center: CGPoint(x: S * x, y: S * y), radius: max(1, S * rad), startAngle: 0, endAngle: 7, clockwise: false)
                    g.fillPath()
                }
                g.setStrokeColor(UIColor(red: 40 / 255, green: 34 / 255, blue: 28 / 255, alpha: 0.45).cgColor)
                g.setLineWidth(max(1, S * 0.05))
                g.move(to: CGPoint(x: S * 0.15, y: S * 0.48))
                g.addLine(to: CGPoint(x: S * 0.42, y: S * 0.52))
                g.addLine(to: CGPoint(x: S * 0.55, y: S * 0.4))
                g.strokePath()
            }
        }
    }
}
