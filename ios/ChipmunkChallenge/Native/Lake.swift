import ChipmunkEngine
import QuartzCore
import UIKit

/* Lakes (engine WATER cells) drawn as one body of water, not as blocks.

   The water is painted into the board's cached image (so blocks on its shore overlap it as they do the tray): one
   rounded outline traced round all the water cells, filled teal-to-deep-teal from top to bottom, darker under a shore
   to the north (the water sits lower than the ground) and lighter along a shore to the south. Over it, LakeLayer adds
   the movement with Core Animation alone (no redraws): a slow sheen sweeping across, and short glints that drift and
   fade. With Reduce Motion on, the water stays still. */

/// A board's water in board points (navigation-grid coordinates × cell size).
struct LakeShape {
    let path: CGPath
    let bounds: CGRect
    /// Centres of the water cells (glints start at some of them).
    let centers: [CGPoint]
    private let water: Set<Int>
    private let W: Int
    private let H: Int
    private let cs: CGFloat

    static let top: UInt32 = 0x58B9C4
    static let deep: UInt32 = 0x2A8199
    /// How far the water's outer edge sits inside its cells, so a sliver of tray shows along a dry shore.
    static let inset: CGFloat = 0.07

    init?(_ lv: Level, cs: CGFloat) {
        let W = lv.W, H = lv.H
        var water = Set<Int>()
        for i in lv.art.cells.indices where lv.art.cells[i] == WATER { water.insert(i) }
        guard !water.isEmpty, cs > 0 else { return nil }
        self.water = water
        self.W = W
        self.H = H
        self.cs = cs
        func wet(_ r: Int, _ c: Int) -> Bool { r >= 0 && c >= 0 && r < H && c < W && water.contains(r * W + c) }
        let p = CGMutablePath()
        var centers: [CGPoint] = []
        let R = cs * 0.5, e = cs * Self.inset
        for i in water.sorted() {
            let r = i / W, c = i % W, n = lv.boardToNav(i)
            let x = CGFloat(n % lv.NW) * cs, y = CGFloat(n / lv.NW) * cs
            let T = wet(r - 1, c), B = wet(r + 1, c), L = wet(r, c - 1), Rt = wet(r, c + 1)
            let rect = CGRect(x: x + (L ? 0 : e), y: y + (T ? 0 : e),
                              width: cs - (L ? 0 : e) - (Rt ? 0 : e), height: cs - (T ? 0 : e) - (B ? 0 : e))
            // A corner is rounded where the water turns outward there (no water on either side of it).
            Self.addRect(p, rect, tl: !T && !L ? R : 0, tr: !T && !Rt ? R : 0, bl: !B && !L ? R : 0, br: !B && !Rt ? R : 0)
            centers.append(CGPoint(x: x + cs / 2, y: y + cs / 2))
        }
        path = p
        bounds = p.boundingBoxOfPath
        self.centers = centers
    }

    /// A rectangle with its own radius at each corner, wound the same way as every other piece so they union.
    private static func addRect(_ p: CGMutablePath, _ r: CGRect, tl: CGFloat, tr: CGFloat, bl: CGFloat, br: CGFloat) {
        p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        if tr > 0 { p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + tr), radius: tr) }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        if br > 0 { p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - br, y: r.maxY), radius: br) }
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        if bl > 0 { p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - bl), radius: bl) }
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
        if tl > 0 { p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + tl, y: r.minY), radius: tl) }
        p.closeSubpath()
    }

    /// Paint the water inside one cell of the board image (y-down point context).
    func paint(_ g: CGContext, cell: CGRect) {
        g.saveGState()
        defer { g.restoreGState() }
        g.clip(to: cell)
        g.addPath(path)
        g.clip()
        let cols = [UIColor(hex: Self.top).cgColor, UIColor(hex: Self.deep).cgColor] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cols, locations: [0, 1]) {
            g.drawLinearGradient(grad, start: CGPoint(x: bounds.midX, y: bounds.minY),
                                 end: CGPoint(x: bounds.midX, y: bounds.maxY), options: [])
        }
        // Shores: shade where ground lies to the north, a pale lip where it lies to the south.
        let c = Int((cell.minX / cs).rounded()) - MG.l, r = Int((cell.minY / cs).rounded()) - MG.t
        func dry(_ rr: Int, _ cc: Int) -> Bool { rr < 0 || cc < 0 || rr >= H || cc >= W || !water.contains(rr * W + cc) }
        if dry(r - 1, c) {
            g.setFillColor(UIColor(hex: 0x0E4A5C, alpha: 0.38).cgColor)
            g.fill(CGRect(x: cell.minX, y: cell.minY, width: cell.width, height: cs * 0.3))
        }
        if dry(r, c - 1) {
            g.setFillColor(UIColor(hex: 0x0E4A5C, alpha: 0.18).cgColor)
            g.fill(CGRect(x: cell.minX, y: cell.minY, width: cs * 0.18, height: cell.height))
        }
        if dry(r + 1, c) {
            g.setFillColor(UIColor(white: 1, alpha: 0.22).cgColor)
            g.fill(CGRect(x: cell.minX, y: cell.maxY - cs * 0.2, width: cell.width, height: cs * 0.2))
        }
    }
}

/// The water's movement, over the painted lake.
final class LakeLayer: CALayer {
    private let maskShape = CAShapeLayer()

    override init() {
        super.init()
        mask = maskShape
        isHidden = true
    }

    override init(layer: Any) { super.init(layer: layer) }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ lake: LakeShape?, cs: CGFloat) {
        sublayers?.forEach { $0.removeFromSuperlayer() }
        guard let lake else {
            isHidden = true
            return
        }
        isHidden = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskShape.frame = bounds.isEmpty ? CGRect(x: 0, y: 0, width: 4000, height: 4000) : bounds
        maskShape.path = lake.path
        defer { CATransaction.commit() }
        let still = UIAccessibility.isReduceMotionEnabled

        // A soft band of light sweeping slowly across, now and then.
        let sheen = CAGradientLayer()
        sheen.frame = lake.bounds.insetBy(dx: -cs, dy: -cs)
        sheen.startPoint = CGPoint(x: 0, y: 0.2)
        sheen.endPoint = CGPoint(x: 1, y: 0.8)
        sheen.colors = [UIColor(white: 1, alpha: 0).cgColor, UIColor(white: 1, alpha: 0.16).cgColor,
                        UIColor(white: 1, alpha: 0).cgColor]
        sheen.locations = [-0.4, -0.25, -0.1]
        addSublayer(sheen)
        if !still {
            let a = CABasicAnimation(keyPath: "locations")
            a.fromValue = [-0.4, -0.25, -0.1]
            a.toValue = [1.1, 1.25, 1.4]
            a.duration = 5.5
            let group = CAAnimationGroup()
            group.animations = [a]
            group.duration = 9
            group.repeatCount = .infinity
            sheen.add(group, forKey: "sheen")
        }

        // Glints: short pale dashes that brighten, drift a little with the breeze and fade.
        var h: UInt32 = UInt32(truncatingIfNeeded: lake.centers.count &* 2_654_435_761)
        func rnd() -> CGFloat {
            h = h &* 1_664_525 &+ 1_013_904_223
            return CGFloat(h) / CGFloat(UInt32.max)
        }
        let count = min(16, max(3, lake.centers.count / 10))
        for _ in 0..<count {
            let p = lake.centers[Int(rnd() * CGFloat(lake.centers.count - 1))]
            let w = cs * (0.7 + rnd() * 0.6), t = max(1, cs * 0.16)
            let dash = CAShapeLayer()
            dash.path = UIBezierPath(roundedRect: CGRect(x: -w / 2, y: -t / 2, width: w, height: t), cornerRadius: t / 2).cgPath
            dash.fillColor = UIColor(white: 1, alpha: 0.75).cgColor
            dash.position = CGPoint(x: p.x + (rnd() - 0.5) * cs, y: p.y + (rnd() - 0.5) * cs)
            dash.opacity = still ? 0.25 : 0
            addSublayer(dash)
            if still { continue }
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.7, 0]
            fade.keyTimes = [0, 0.45, 1]
            let drift = CABasicAnimation(keyPath: "position.x")
            drift.byValue = cs * 0.8
            let group = CAAnimationGroup()
            group.animations = [fade, drift]
            group.duration = 2.4 + rnd() * 2.2
            group.repeatCount = .infinity
            group.timeOffset = rnd() * group.duration
            dash.add(group, forKey: "glint")
        }
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        maskShape.frame = bounds
    }
}
