import SwiftUI

/* Mystery boxes in the HUD and on the win card (the web page's .mbox, .heldchip and .reveal). */

/// `.mbox`: a rounded square with a rainbow turning inside it and a white "?" (grey and still when `grey`).
struct MysteryBoxIcon: View {
    var size: CGFloat = 20
    var grey = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let rainbow = Gradient(colors: [0xFF4D4D, 0xFFA53A, 0xFFE14D, 0x5FD35F, 0x4DC3FF, 0x6B6BFF, 0xC065FF,
                                                   0xFF4D4D].map { Color(hex: $0) })

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        TimelineView(.animation(paused: grey || reduceMotion)) { tl in
            let turn = grey || reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate / 1.6 * 360
            ZStack {
                if grey {
                    Color(hex: 0xBBBBBB)
                } else {
                    AngularGradient(gradient: Self.rainbow, center: .center)
                        .frame(width: size * 2.2, height: size * 2.2)
                        .rotationEffect(.degrees(turn.truncatingRemainder(dividingBy: 360)))
                }
                Text("?")
                    .font(.system(size: size * 0.7, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: Color(hex: 0x1F2A18), radius: 0.6)
                    .shadow(color: Color(hex: 0x1F2A18), radius: 0, y: 1)
            }
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color(hex: 0x1F2A18), lineWidth: max(2, size * 0.07)))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// `.heldchip`: the boxes on hold this try, behind a lock; greyed with ✕ once help was used. It pops when a box
/// arrives and shakes when tapped or when help loses it.
struct HeldChip: View {
    @ObservedObject var model: GameModel
    @SwiftUI.State private var pop: CGFloat = 1
    @SwiftUI.State private var shake: CGFloat = 0

    var body: some View {
        let lost = model.helped
        Button { model.shakeHeld() } label: {
            HStack(spacing: 3) {
                MysteryBoxIcon(size: 20, grey: lost)
                if model.held.count > 1 {
                    Text("×\(model.held.count)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x1F2A18))
                }
                Text(lost ? "✕" : "🔒").font(.system(size: 11))
            }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 15).fill(lost ? Color(hex: 0xEEEEEE) : Color(hex: 0xFFF8E1)))
            .overlay(RoundedRectangle(cornerRadius: 15)
                .strokeBorder(lost ? Color(hex: 0xBBBBBB) : Color(hex: 0xC9A24A), style: StrokeStyle(lineWidth: 2, dash: [4, 3])))
            .opacity(lost ? 0.7 : 1)
            .scaleEffect(pop)
            .rotationEffect(.degrees(Double(shake) * 1.5))
            .offset(x: shake)
        }
        .buttonStyle(.plain)
        .accessibilityLabel((model.held.count > 1 ? "\(model.held.count) mystery boxes" : "Mystery box")
                            + (lost ? " lost: help was used" : " on hold: clear the board without help to open"))
        .onChange(of: model.heldPop) { _, _ in
            withAnimation(.easeOut(duration: 0.2)) { pop = 1.25 }
            withAnimation(.easeIn(duration: 0.3).delay(0.2)) { pop = 1 }
        }
        .onChange(of: model.heldShake) { _, _ in
            Task { @MainActor in
                for x in [-4, 4, -3, 3, 0] as [CGFloat] {
                    withAnimation(.easeInOut(duration: 0.08)) { shake = x }
                    try? await Task.sleep(for: .milliseconds(90))
                }
            }
        }
    }
}

/// `.reveal`: the win card opens the boxes. They shake, burst, and the tools inside pop out. Boxes lost to help show
/// grey with a red ✕.
struct BoxRevealView: View {
    let box: GameModel.BoxReveal
    @SwiftUI.State private var phase = 0     // 0 shut, 1 shaking, 2 burst, 3 tools shown
    @SwiftUI.State private var wobble: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var n: Int { min(3, max(1, box.count)) }
    private var boxSize: CGFloat { n > 1 ? 52 : 64 }

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(0..<n, id: \.self) { _ in MysteryBoxIcon(size: boxSize, grey: box.lost) }
            }
            .opacity(box.lost ? 0.55 : phase >= 2 ? 0 : 1)
            .scaleEffect(phase >= 2 && !box.lost ? 1.3 : 1)
            .rotationEffect(.degrees(wobble))
            if box.lost {
                Text("✕").font(.system(size: 44, weight: .black)).foregroundStyle(Color(hex: 0xC62828))
            } else {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xFFF6B0), Color(hex: 0xFFD54A), .clear],
                                         center: .center, startRadius: 0, endRadius: 60))
                    .frame(width: 120, height: 120)
                    .scaleEffect(phase >= 2 ? 1.2 : 0.3)
                    .opacity(phase == 2 ? 1 : 0)
                HStack(spacing: n > 1 ? 10 : 14) {
                    ForEach(Array(box.tools.enumerated()), id: \.offset) { _, t in
                        HStack(spacing: 3) {
                            Text(t.icon).font(.system(size: n > 1 ? 34 : 46))
                            Text("+1").font(.system(size: n > 1 ? 16 : 20, weight: .heavy)).foregroundStyle(Color(hex: 0x2E7D32))
                        }
                    }
                }
                .scaleEffect(phase >= 3 ? 1 : 0.2)
                .opacity(phase >= 3 ? 1 : 0)
            }
        }
        .frame(minWidth: 84, minHeight: 84)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(box.lost ? "Mystery box lost" : "Mystery box: " + box.tools.map(\.name).joined(separator: ", "))
        .task {
            if box.lost { return }
            if reduceMotion {
                phase = 3
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            phase = 1
            for a in [-8.0, 8, -6, 6, -3, 0] {
                withAnimation(.easeInOut(duration: 0.11)) { wobble = a }
                try? await Task.sleep(for: .milliseconds(115))
            }
            withAnimation(.easeOut(duration: 0.35)) { phase = 2 }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { phase = 3 }
        }
    }
}
