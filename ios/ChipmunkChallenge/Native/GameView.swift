import SpriteKit
import SwiftUI

/// The native play screen: a header with the board's name and controls, the SpriteKit board, and overlays for
/// building, winning and getting stuck.
struct GameView: View {
    @StateObject private var model: GameModel
    @State private var scene: GameScene

    init() {
        let m = GameModel()
        _model = StateObject(wrappedValue: m)
        _scene = State(initialValue: GameScene(model: m))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
                .overlay { overlay }
        }
        .background(Color(uiColor: Palette.wood))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { model.previous() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(RoundButton())
                .disabled(model.boardIndex == 0)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.subtitle.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(model.title)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
            Button { model.fast.toggle() } label: {
                Image(systemName: model.fast ? "forward.fill" : "forward")
            }
            .buttonStyle(RoundButton(active: model.fast))
            Button { model.restart() } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(RoundButton())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .foregroundStyle(Color(red: 0.12, green: 0.18, blue: 0.1))
        .background(Color(red: 0.93, green: 0.95, blue: 0.91))
    }

    @ViewBuilder private var overlay: some View {
        switch model.status {
        case .building:
            Card {
                ProgressView().controlSize(.large)
                Text("Building board…").font(.headline)
            }
        case .won:
            Card {
                Text("🐿️").font(.system(size: 54))
                Text("Board cleared!").font(.system(size: 26, weight: .black, design: .rounded))
                Button("Next level") { model.next() }.buttonStyle(BigButton())
                Button("Play again") { model.restart() }.buttonStyle(.borderless)
            }
        case .stuck:
            Card {
                Text("Out of moves").font(.system(size: 26, weight: .black, design: .rounded))
                Text("Every slot is full and no critter can reach its color.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Try again") { model.restart() }.buttonStyle(BigButton())
                Button("New board") { model.newBoard() }.buttonStyle(.borderless)
            }
        case .failed(let message):
            Card {
                Text(message).multilineTextAlignment(.center)
                Button("Next level") { model.next() }.buttonStyle(BigButton())
            }
        case .playing:
            EmptyView()
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 14) { content }
            .padding(24)
            .frame(maxWidth: 300)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .shadow(radius: 12)
            .transition(.scale.combined(with: .opacity))
    }
}

private struct RoundButton: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .frame(width: 44, height: 40)
            .background(active ? Color(red: 0.82, green: 0.9, blue: 0.78) : Color(red: 0.86, green: 0.9, blue: 0.84),
                        in: RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

private struct BigButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(red: 0.12, green: 0.16, blue: 0.1), in: RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
