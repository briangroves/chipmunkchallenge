import CoreText
import SwiftUI
import UIKit

/// Colors, fonts and measurements from the web game's CSS, so the native screens match it.
enum Theme {
    // :root
    static let page = Color(hex: 0x1F2F1B)           // body background
    static let card = Color(hex: 0xEEF4E8)           // --card
    static let ink = Color(hex: 0x1D2419)            // --ink
    static let sub = Color(hex: 0x5D6B54)            // .topbar .sub
    static let button = Color(hex: 0xDBE6D2)         // .ib, .navback
    static let darkInk = Color(hex: 0x1F2A18)        // #speedBtn.on background, tool badge
    static let gold = Color(hex: 0xFFD23F)

    // Board canvas
    static let trayIn: UInt32 = 0xCFC3A6             // TRAY_IN
    static let walk: UInt32 = 0xC9BB98               // WALK
    static let rock: UInt32 = 0x8B8780               // ROCK_HEX

    /// Registers the game's fonts (the same WOFF2 files the web page uses). Call once at launch.
    static func registerFonts() {
        for name in ["LilitaOne", "Nunito"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "woff2") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// --f-display: Lilita One.
    static func display(_ size: CGFloat) -> Font { .custom("LilitaOne", fixedSize: size) }

    /// --f-body: Nunito at a CSS weight (500, 700, 800, 900).
    static func body(_ size: CGFloat, _ weight: Int = 400) -> Font {
        .custom(nunitoName(weight), fixedSize: size)
    }

    static func uiDisplay(_ size: CGFloat) -> UIFont {
        UIFont(name: "LilitaOne", size: size) ?? .systemFont(ofSize: size, weight: .black)
    }

    static func nunitoName(_ weight: Int) -> String {
        switch weight {
        case ..<550: return "Nunito-Medium"
        case ..<750: return "Nunito-Bold"
        case ..<850: return "Nunito-ExtraBold"
        default: return "Nunito-Black"
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// JS `mix(h, t, a)`: blend two colors channel by channel, rounding like the page does.
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

/// The four critter tones per color (JS buildTones).
struct Tone {
    let face: UIColor
    let hi: UIColor
    let lo: UIColor
    let gloss: UIColor

    init(_ h: UInt32) {
        face = UIColor(hex: h)
        hi = mix(h, 0xFFFFFF, 0.45)
        lo = mix(h, 0x000000, 0.38)
        gloss = mix(h, 0xFFFFFF, 0.7)
    }
}
