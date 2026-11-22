import SwiftUI
import UIKit

// The game's blocks, so a board here looks the way players will see it: copied from the game's block sprites
// (ios/ChipmunkChallenge/Native/BoardView.swift SpriteCache.makeSprite) and the tray it sits in (paintOff).
// Keep the two in step if the game's look changes.

private let TRAY_IN: UInt32 = 0xCFC3A6   // Theme.trayIn
private let WALK: UInt32 = 0xC9BB98      // Theme.walk

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// JS `mix(h, t, a)`: blend two colors channel by channel, rounding like the game does.
func mix(_ h: UInt32, _ t: UInt32, _ a: Double) -> UIColor {
    func ch(_ k: UInt32) -> CGFloat {
        let v = Double((h >> k) & 0xFF) * (1 - a) + Double((t >> k) & 0xFF) * a
        return CGFloat(JSRound(v)) / 255
    }
    return UIColor(red: ch(16), green: ch(8), blue: ch(0), alpha: 1)
}

/// JS Math.round.
func JSRound(_ x: Double) -> Double {
    let f = x.rounded(.down)
    return x - f >= 0.5 ? f + 1 : f
}

/// A whole board drawn like the game: the sandy tray, a one-block margin, and every block as the game's cube.
enum BoardArt {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ rows: [String], width: CGFloat, scale: CGFloat) -> UIImage? {
        let grid = rows.map(Array.init)
        let W = grid.first?.count ?? 0, H = grid.count
        guard W > 0, H > 0, width > 0 else { return nil }
        let NW = W + 2, NH = H + 2
        let cs = max(2, (width / CGFloat(NW) * scale).rounded(.down) / scale)   // whole device pixels, like the game
        let key = "\(rows.joined(separator: "/"))|\(cs)|\(scale)" as NSString
        if let img = cache.object(forKey: key) { return img }
        var sprites = Sprites(cs: cs, scale: scale)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = scale
        let size = CGSize(width: CGFloat(NW) * cs, height: CGFloat(NH) * cs + cs * Sprites.depth)
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let g = ctx.cgContext
            g.setFillColor(UIColor(hex: WALK).cgColor)
            g.addPath(UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: size.height),
                                   cornerRadius: cs * 1.3).cgPath)
            g.fillPath()
            g.setFillColor(UIColor(hex: TRAY_IN).cgColor)
            g.fill(CGRect(x: cs, y: cs, width: CGFloat(W) * cs, height: CGFloat(H) * cs))
            func filled(_ r: Int, _ c: Int) -> Bool {
                r >= 0 && c >= 0 && r < H && c < W && PALETTE[grid[r][c]] != nil
            }
            for r in 0..<H {
                for c in 0..<W {
                    guard let h = PALETTE[grid[r][c]] else { continue }
                    // BoardView.cornerMask: a corner is rounded only where both its sides are open.
                    let T = !filled(r - 1, c), B = !filled(r + 1, c), L = !filled(r, c - 1), R = !filled(r, c + 1)
                    let mask = (T && L ? 1 : 0) | (T && R ? 2 : 0) | (B && L ? 4 : 0) | (B && R ? 8 : 0)
                    // A block with a block under it shows only its top face; the rest show their side band too.
                    sprites.block(g, CGFloat(c + 1) * cs, CGFloat(r + 1) * cs, cs, h, filled(r + 1, c), mask)
                }
            }
        }
        cache.setObject(img, forKey: key)
        return img
    }
}

/// The game's SpriteCache, keyed by color instead of the level's color index.
private struct Sprites {
    static let depth: CGFloat = 0.42
    private var S = 0
    private var D = 0
    private var cache: [String: UIImage] = [:]

    init(cs: CGFloat, scale: CGFloat) {
        S = max(4, Int(JSRound(Double(cs * scale))))
        D = max(2, Int(JSRound(Double(S) * Double(Self.depth))))
    }

    mutating func block(_ g: CGContext, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ h: UInt32, _ flat: Bool, _ mask0: Int) {
        let mask = flat ? mask0 & 3 : mask0
        let k = "\(h)-\(flat)-\(mask)"
        let img = cache[k] ?? makeSprite(h, flat, mask)
        cache[k] = img
        UIGraphicsPushContext(g)
        img.draw(in: CGRect(x: x, y: y, width: s, height: flat ? s : s * (1 + Self.depth)))
        UIGraphicsPopContext()
    }

    private func makeSprite(_ h: UInt32, _ flat: Bool, _ mask: Int) -> UIImage {
        let S = CGFloat(self.S), D = flat ? 0 : CGFloat(self.D)
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
        }
    }
}
