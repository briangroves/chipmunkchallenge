import SwiftUI

/// The table backgrounds from the web page's settings (JS TABLES and the `.t-*` styles).
enum Table: String, CaseIterable, Identifiable {
    case wood, linen, felt, sky, candy, night

    var id: String { rawValue }

    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// Coins to unlock this table (0 = free). The tables give coins something to save up for.
    var price: Int {
        switch self {
        case .wood, .linen: return 0
        case .sky: return 1000
        case .felt: return 1500
        case .candy: return 2500
        case .night: return 4000
        }
    }

    /// Dark tables want light text drawn straight on them (the title on the home screen).
    var isDark: Bool { self == .felt || self == .night }
}

/// The chosen table, edge to edge.
struct TableBackground: View {
    let table: Table

    var body: some View {
        switch table {
        case .wood: WoodBackground()
        case .linen: LinenBackground()
        case .felt:
            // radial-gradient(circle at 50% 25%, #43a06a, #215c39), out to the farthest corner
            GeometryReader { g in
                let far = hypot(g.size.width / 2, g.size.height * 0.75)
                RadialGradient(colors: [Color(hex: 0x43A06A), Color(hex: 0x215C39)],
                               center: UnitPoint(x: 0.5, y: 0.25), startRadius: 0, endRadius: far)
            }
        case .sky:
            LinearGradient(colors: [Color(hex: 0xB9E3FF), Color(hex: 0xEAF8FF)], startPoint: .top, endPoint: .bottom)
        case .candy: CandyBackground()
        case .night: NightBackground()
        }
    }
}

/// `.t-linen`: cream with faint 1-point threads every 4 points both ways.
private struct LinenBackground: View {
    var body: some View {
        Canvas { g, size in
            g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xF4ECDC)))
            let thread = Color(red: 90 / 255, green: 70 / 255, blue: 40 / 255, opacity: 0.05)
            var p = Path()
            var x: CGFloat = 0
            while x < size.width { p.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)); x += 4 }
            var y: CGFloat = 0
            while y < size.height { p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 4 }
            g.fill(p, with: .color(thread))
        }
    }
}

/// `.t-candy`: pink and white stripes 14 points wide at 45°.
private struct CandyBackground: View {
    var body: some View {
        Canvas { g, size in
            g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xFFF1F7)))
            // Stripes run across the 45° gradient line, so they climb from bottom left to top right.
            let period: CGFloat = 28 * sqrt(2), band: CGFloat = 14 * sqrt(2)
            var p = Path()
            var t: CGFloat = -size.height
            while t < size.width + size.height {
                p.move(to: CGPoint(x: t, y: size.height))
                p.addLine(to: CGPoint(x: t + band, y: size.height))
                p.addLine(to: CGPoint(x: t + band + size.height, y: 0))
                p.addLine(to: CGPoint(x: t + size.height, y: 0))
                p.closeSubpath()
                t += period
            }
            g.fill(p, with: .color(Color(hex: 0xFFD9E8)))
        }
    }
}

/// `.t-night`: deep blue, lighter at the top, with a grid of faint stars every 22 points.
private struct NightBackground: View {
    var body: some View {
        Canvas { g, size in
            let far = hypot(size.width / 2, size.height)
            g.fill(Path(CGRect(origin: .zero, size: size)),
                   with: .radialGradient(Gradient(colors: [Color(hex: 0x2B3D6A), Color(hex: 0x121A30)]),
                                         center: CGPoint(x: size.width / 2, y: 0), startRadius: 0, endRadius: far))
            var dots = Path()
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    x += 22
                }
                y += 22
            }
            g.fill(dots, with: .color(.white.opacity(0.14)))
        }
    }
}

/// `.sw-btn`: a 34-point swatch of a table; the chosen one has a dark border.
struct TableSwatch: View {
    let table: Table
    let on: Bool
    var owned = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                TableBackground(table: table)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .circular))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .circular).strokeBorder(.black.opacity(0.12), lineWidth: 1))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .circular).strokeBorder(on ? Theme.ink : .clear, lineWidth: 2))
                    .overlay {
                        if !owned {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 1.5)
                        }
                    }
                Text(owned ? " " : table.price >= 1000 ? "\(table.price / 1000)k" : "\(table.price)")
                    .font(Theme.body(10, 800))
                    .foregroundStyle(Color(hex: 0x8A6500))
            }
        }
        .buttonStyle(Pressable())
        .accessibilityLabel(owned ? "\(table.label) table" : "\(table.label) table, \(table.price) coins")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
