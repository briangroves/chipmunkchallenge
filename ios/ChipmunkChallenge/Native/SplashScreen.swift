import SwiftUI

/// The launch splash: the same sky and grass as the level intro, the title popping in, and the chipmunk scampering
/// onto its stump and stuffing an acorn in its cheeks. It ends on its own after the acorn goes in, or on a tap, then
/// calls `done` so the root can fade it out. The system launch screen is the sky's top color, so launch flows into it.
struct SplashScreen: View {
    let done: () -> Void
    @SwiftUI.State private var go = false
    @SwiftUI.State private var titleIn = false

    /// When the splash ends by itself: just after the cheeks puff up (the intro's acorn is in by 2.25s).
    private static let length: TimeInterval = 2.7

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = min(geo.size.height, w * 1.1)
            ZStack {
                LinearGradient(stops: [.init(color: Color(hex: 0xBFE3FF), location: 0), .init(color: Color(hex: 0xE3F4FF), location: 0.55),
                                       .init(color: Color(hex: 0xF5FBEF), location: 1)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                SceneLayer.grass
                    .frame(height: (geo.size.height - h) / 2 + 1 + geo.safeAreaInsets.bottom)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .offset(y: geo.safeAreaInsets.bottom)
                SceneCanvas(run: GameModel.SceneRun(kind: .intro, id: -1), size: CGSize(width: w, height: h),
                            ready: { true }, go: { go }) {
                    done()
                }
                .frame(width: w, height: h)
                VStack(spacing: -6) {
                    Text("Chipmunk")
                    Text("Challenge")
                }
                .font(Theme.display(60))
                .foregroundStyle(Theme.darkInk)
                .shadow(color: .white.opacity(0.7), radius: 0, y: 3)
                .scaleEffect(titleIn ? 1 : 0.5)
                .opacity(titleIn ? 1 : 0)
                .padding(.top, 24)
                .frame(maxHeight: .infinity, alignment: .top)
                // Over everything, so a tap anywhere skips (the 3D view would otherwise take the touch).
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { go = true }
                    .ignoresSafeArea()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chipmunk Challenge")
        .onAppear {
            withAnimation(.interpolatingSpring(stiffness: 220, damping: 13).delay(0.1)) { titleIn = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.length) { go = true }
        }
    }
}
