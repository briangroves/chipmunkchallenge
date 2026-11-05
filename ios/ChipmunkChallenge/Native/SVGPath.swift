import SwiftUI

/// A shape from an SVG path string (the web page's inline icons), scaled from its viewBox into the frame.
struct SVGShape: Shape {
    let d: String
    let viewBox: CGSize

    func path(in rect: CGRect) -> Path {
        let p = SVGPathParser.parse(d)
        let t = CGAffineTransform(scaleX: rect.width / viewBox.width, y: rect.height / viewBox.height)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return p.applying(t)
    }
}

/// The web page's icons.
enum Icons {
    static let undo = SVGShape(d: "M12.5 8c-2.65 0-5.05 1-6.9 2.6L2 7v9h9l-3.62-3.62A7.97 7.97 0 0 1 12.5 10.5c3.54 0 6.55 2.31 7.6 5.5l2.37-.78C21.08 11.03 17.15 8 12.5 8z", viewBox: CGSize(width: 24, height: 24))
    static let speed = SVGShape(d: "M4 18l8.5-6L4 6v12zm9-12v12l8.5-6L13 6z", viewBox: CGSize(width: 24, height: 24))
    static let restart = SVGShape(d: "M12 5V2L7 6l5 4V7a5 5 0 1 1-5 5H5a7 7 0 1 0 7-7z", viewBox: CGSize(width: 24, height: 24))
    static let gear = SVGShape(d: "M19.4 13a7.7 7.7 0 0 0 0-2l2.1-1.6-2-3.5-2.5 1a7.4 7.4 0 0 0-1.7-1L15 3.3h-4l-.4 2.6a7.4 7.4 0 0 0-1.7 1l-2.5-1-2 3.5L6.6 11a7.7 7.7 0 0 0 0 2l-2.1 1.6 2 3.5 2.5-1a7.4 7.4 0 0 0 1.7 1l.4 2.6h4l.4-2.6a7.4 7.4 0 0 0 1.7-1l2.5 1 2-3.5zM12 15.5a3.5 3.5 0 1 1 0-7 3.5 3.5 0 0 1 0 7z", viewBox: CGSize(width: 24, height: 24))
    static let heart = SVGShape(d: "M12 21s-7.6-4.7-10.1-9.4C.4 8.4 2 4.1 6 3.4c2.4-.4 4.5.9 6 3 1.5-2.1 3.6-3.4 6-3 4 .7 5.6 5 4.1 8.2C19.6 16.3 12 21 12 21z", viewBox: CGSize(width: 24, height: 22))
}

/// Parses SVG path data: M L H V C S Q T A Z, absolute and relative.
enum SVGPathParser {
    static func parse(_ d: String) -> Path {
        var tokens = Tokenizer(d)
        var path = Path()
        var cur = CGPoint.zero, start = CGPoint.zero
        var lastCtrl: CGPoint?
        var cmd: Character = "M"
        while let c = tokens.command(default: cmd) {
            cmd = c
            let rel = c.isLowercase
            func pt() -> CGPoint? {
                guard let x = tokens.number(), let y = tokens.number() else { return nil }
                return rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
            }
            switch c.uppercased().first! {
            case "M":
                guard let p = pt() else { return path }
                path.move(to: p)
                cur = p
                start = p
                lastCtrl = nil
                cmd = rel ? "l" : "L"           // further pairs are line-tos
            case "L":
                guard let p = pt() else { return path }
                path.addLine(to: p)
                cur = p
                lastCtrl = nil
            case "H":
                guard let x = tokens.number() else { return path }
                cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y)
                path.addLine(to: cur)
                lastCtrl = nil
            case "V":
                guard let y = tokens.number() else { return path }
                cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y)
                path.addLine(to: cur)
                lastCtrl = nil
            case "C":
                guard let c1 = pt(), let c2 = pt(), let p = pt() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                lastCtrl = c2
                cur = p
            case "S":
                let c1 = lastCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                guard let c2 = pt(), let p = pt() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                lastCtrl = c2
                cur = p
            case "Q":
                guard let c1 = pt(), let p = pt() else { return path }
                path.addQuadCurve(to: p, control: c1)
                lastCtrl = c1
                cur = p
            case "T":
                let c1 = lastCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                guard let p = pt() else { return path }
                path.addQuadCurve(to: p, control: c1)
                lastCtrl = c1
                cur = p
            case "A":
                guard let rx = tokens.number(), let ry = tokens.number(), let rot = tokens.number(),
                      let large = tokens.flag(), let sweep = tokens.flag(), let p = pt() else { return path }
                arc(&path, from: cur, to: p, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                cur = p
                lastCtrl = nil
            case "Z":
                path.closeSubpath()
                cur = start
                lastCtrl = nil
            default:
                return path
            }
        }
        return path
    }

    /// SVG endpoint arc → cubic segments (SVG spec, appendix F.6).
    private static func arc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat,
                            rotation: CGFloat, large: Bool, sweep: Bool) {
        if p0 == p1 { return }
        var rx = abs(rx0), ry = abs(ry0)
        if rx == 0 || ry == 0 { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180, cp = cos(phi), sp = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cp * dx + sp * dy, y1 = -sp * dx + cp * dy
        let lam = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lam > 1 { rx *= sqrt(lam); ry *= sqrt(lam) }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var co = sqrt(max(0, num / den))
        if large == sweep { co = -co }
        let cxp = co * rx * y1 / ry, cyp = -co * ry * x1 / rx
        let cx = cp * cxp - sp * cyp + (p0.x + p1.x) / 2, cy = sp * cxp + cp * cyp + (p0.y + p1.y) / 2
        func ang(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let t1 = ang(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
        var dt = ang((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
        if !sweep && dt > 0 { dt -= 2 * .pi } else if sweep && dt < 0 { dt += 2 * .pi }
        let segs = max(1, Int(ceil(abs(dt) / (.pi / 2))))
        let delta = dt / CGFloat(segs)
        let k = 4 / 3 * tan(delta / 4)
        var t = t1
        for _ in 0..<segs {
            let c1 = cos(t), s1 = sin(t), c2 = cos(t + delta), s2 = sin(t + delta)
            func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: cx + cp * rx * x - sp * ry * y, y: cy + sp * rx * x + cp * ry * y)
            }
            path.addCurve(to: map(c2, s2), control1: map(c1 - k * s1, s1 + k * c1), control2: map(c2 + k * s2, s2 - k * c2))
            t += delta
        }
    }

    private struct Tokenizer {
        let chars: [Character]
        var i = 0

        init(_ s: String) { chars = Array(s) }

        mutating func skip() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
        }

        /// The next command letter, or the previous one again when numbers follow (implicit repeat).
        mutating func command(default d: Character) -> Character? {
            skip()
            guard i < chars.count else { return nil }
            if chars[i].isLetter && chars[i] != "e" && chars[i] != "E" {
                defer { i += 1 }
                return chars[i]
            }
            return d
        }

        mutating func flag() -> Bool? {
            skip()
            guard i < chars.count else { return nil }
            defer { i += 1 }
            return chars[i] == "1"
        }

        mutating func number() -> CGFloat? {
            skip()
            let s = i
            if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
            var dot = false
            while i < chars.count {
                let c = chars[i]
                if c.isNumber { i += 1 }
                else if c == "." && !dot { dot = true; i += 1 }
                else if (c == "e" || c == "E") && i + 1 < chars.count {
                    i += 1
                    if chars[i] == "-" || chars[i] == "+" { i += 1 }
                }
                else { break }
            }
            guard i > s, let v = Double(String(chars[s..<i])) else { i = s; return nil }
            return CGFloat(v)
        }
    }
}
