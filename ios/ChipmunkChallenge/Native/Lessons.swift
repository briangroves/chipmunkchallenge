import SwiftUI

/// What's shown before a board starts (GameModel.Lesson): the how-to-play cards before the very first board, or a
/// new tool's card once it's due (after level 1, then every 2 levels). It sits over the level's splash, which waits
/// on its Start button underneath.
struct LessonOverlay: View {
    @ObservedObject var model: GameModel
    let lesson: GameModel.Lesson

    var body: some View {
        ZStack {
            Color(red: 20 / 255, green: 30 / 255, blue: 15 / 255, opacity: 0.55)
                .ignoresSafeArea()
                // Taps on the dim backdrop do nothing: the lesson ends only on its own button.
                .contentShape(Rectangle())
                .onTapGesture {}
            Group {
                switch lesson {
                case .howToPlay: HowToPlay { model.finishLesson() }
                case .tool(let t): ToolLesson(tool: t) { model.finishLesson() }
                }
            }
            .padding(22)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 22, style: .circular).fill(.white)
                .shadow(color: .black.opacity(0.3), radius: 15, y: 10))
            .padding(16)
        }
    }
}

// MARK: - How to play

/// Four cards, one idea each, with Back / Next and page dots. The last card's button ends the lesson.
private struct HowToPlay: View {
    let done: () -> Void
    @SwiftUI.State private var page = {
        #if DEBUG
        min(3, max(0, UserDefaults.standard.integer(forKey: "lessonPage")))
        #else
        0
        #endif
    }()

    private struct Card {
        let title: String
        let text: String
    }

    private let cards = [
        Card(title: "Clear the picture",
             text: "Every picture is made of colored blocks. Clear every block to win the level."),
        Card(title: "Tap a nest",
             text: "Tap the front nest of any column. It hops up into a holding slot, and its chipmunks run out to "
                + "collect blocks of their color. The number is how many chipmunks are inside: one block each."),
        Card(title: "Work from the outside in",
             text: "Chipmunks can only reach blocks they can get to from the edge. Clear the outer colors first "
                + "to open a path to the ones inside."),
        Card(title: "Keep a slot free",
             text: "A nest stays in its slot until all its chipmunks are out. If every slot fills with nests that "
                + "can't reach their color, you're stuck. Plan ahead!"),
    ]

    var body: some View {
        VStack(spacing: 14) {
            Text("How to play")
                .font(Theme.body(13, 800))
                .foregroundStyle(Color(hex: 0x8A9682))
                .textCase(.uppercase)
            Picture(page: page)
                .frame(height: 150)
                .id(page)
                .transition(.opacity)
            Text(cards[page].title)
                .font(Theme.display(26))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(cards[page].text)
                .font(Theme.body(15, 500))
                .foregroundStyle(Color(hex: 0x4A5841))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 88, alignment: .top)
            HStack(spacing: 7) {
                ForEach(cards.indices, id: \.self) { k in
                    Circle().fill(k == page ? Theme.ink : Color(hex: 0xD6DCCF)).frame(width: 8, height: 8)
                }
            }
            .accessibilityHidden(true)
            HStack(spacing: 8) {
                if page > 0 {
                    Button { withAnimation(.easeOut(duration: 0.2)) { page -= 1 } } label: { Text("Back").bigLabel(alt: true) }
                }
                Button {
                    if page < cards.count - 1 {
                        withAnimation(.easeOut(duration: 0.2)) { page += 1 }
                    } else {
                        done()
                    }
                } label: {
                    Text(page < cards.count - 1 ? "Next" : "Let's play!").bigLabel(alt: false)
                }
            }
            .buttonStyle(Pressable())
        }
        .accessibilityElement(children: .contain)
    }
}

/// Each card's picture, drawn with the game's own nest tiles and blocks.
private struct Picture: View {
    let page: Int

    static let orange: UInt32 = 0xFB8C00
    static let green: UInt32 = 0x43A047
    static let blue: UInt32 = 0x1E88E5
    static let red: UInt32 = 0xE53935

    var body: some View {
        switch page {
        case 0: Mosaic(eaten: [])
        case 1: tapNest
        case 2: Mosaic(eaten: Set([0, 1, 2, 3, 4, 5, 6, 11, 12]), critters: true)
        default: fullSlots
        }
    }

    /// A column of nests with a finger on the front one, and the slot row it hops up to.
    private var tapNest: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(spacing: 8) {
                HStack(spacing: 5) {
                    NestTile(color: Self.orange, count: 3, size: 40, fontSize: 18, front: false, key: false)
                    ForEach(0..<3, id: \.self) { _ in EmptySlot(size: 40) }
                }
                Text("Slots").font(Theme.body(12, 800)).foregroundStyle(Color(hex: 0x8A9682))
            }
            Image(systemName: "arrow.up.left")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Color(hex: 0x8A9682))
            VStack(spacing: 6) {
                NestTile(color: Self.orange, count: 3, size: 40, fontSize: 18, front: true, key: false)
                    .overlay(alignment: .bottomTrailing) { Text("👆").font(.system(size: 26)).offset(x: 14, y: 16) }
                NestTile(color: Self.blue, count: 2, size: 40, fontSize: 18, front: false, key: false)
                NestTile(color: Self.green, count: 4, size: 40, fontSize: 18, front: false, key: false)
                    .opacity(0.6)
            }
        }
    }

    /// Four full slots and the last one free.
    private var fullSlots: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                NestTile(color: Self.orange, count: 2, size: 44, fontSize: 19, front: false, key: false)
                NestTile(color: Self.blue, count: 5, size: 44, fontSize: 19, front: false, key: false)
                NestTile(color: Self.red, count: 1, size: 44, fontSize: 19, front: false, key: false)
                NestTile(color: Self.green, count: 3, size: 44, fontSize: 19, front: false, key: false)
                EmptySlot(size: 44)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .circular)
                        .strokeBorder(Color(hex: 0x2E7D32), style: StrokeStyle(lineWidth: 2.5, dash: [5, 4])))
            }
            Text("One slot left: choose carefully")
                .font(Theme.body(12, 800))
                .foregroundStyle(Color(hex: 0x2E7D32))
        }
    }
}

/// A 6×6 picture in blocks: a blue outside around a green ring and an orange middle. `eaten` cells are open
/// (cleared from the edge), with chipmunks at the edge of the open area when `critters` is set.
private struct Mosaic: View {
    let eaten: Set<Int>
    var critters = false
    private let n = 6

    var body: some View {
        let cell: CGFloat = 22
        ZStack(alignment: .topLeading) {
            VStack(spacing: 2) {
                ForEach(0..<n, id: \.self) { r in
                    HStack(spacing: 2) {
                        ForEach(0..<n, id: \.self) { c in
                            let i = r * n + c
                            if eaten.contains(i) {
                                RoundedRectangle(cornerRadius: 4, style: .circular)
                                    .strokeBorder(Color(hex: 0xCBBF9F), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                    .frame(width: cell, height: cell)
                            } else {
                                Block(color: color(r, c), size: cell)
                            }
                        }
                    }
                }
            }
            if critters {
                // Chipmunks in the cleared edge, reaching for the next blocks in.
                Text("🐿️").font(.system(size: 17)).frame(width: cell, height: cell).offset(x: 2 * (cell + 2), y: 0)
                Text("🐿️").font(.system(size: 17)).frame(width: cell, height: cell).offset(x: 0, y: 2 * (cell + 2))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .circular).fill(Color(hex: 0xF6F1E4)))
    }

    private func color(_ r: Int, _ c: Int) -> UInt32 {
        let ring = min(r, c, n - 1 - r, n - 1 - c)
        return ring == 0 ? Picture.blue : ring == 1 ? Picture.green : Picture.orange
    }
}

/// One block of the picture: its color with a darker lower edge.
private struct Block: View {
    let color: UInt32
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .circular)
            .fill(Color(hex: color))
            .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.25)).frame(height: 3) }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .circular))
            .frame(width: size, height: size)
    }
}

/// An empty holding slot, as on the board.
private struct EmptySlot: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .circular)
            .fill(Color(hex: 0xF1ECE0))
            .background(RoundedRectangle(cornerRadius: 14, style: .circular).fill(.black.opacity(0.12)).offset(y: 3))
            .frame(width: size, height: size)
    }
}

// MARK: - A new tool

/// A tool's lesson: what it does, how to use it, and the 3 that come with it.
private struct ToolLesson: View {
    let tool: Tool
    let done: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("New tool unlocked!")
                .font(Theme.body(13, 800))
                .foregroundStyle(Color(hex: 0x2E7D32))
                .textCase(.uppercase)
            ToolIcon(tool: tool, size: 56)
                .frame(width: 96, height: 96)
                .background(Circle().fill(Color(hex: 0xFFF8E1)))
                .overlay(alignment: .topTrailing) {
                    Text("×\(GameModel.lessonGift)")
                        .font(Theme.body(15, 900))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 28)
                        .background(Capsule().fill(Theme.darkInk))
                        .background(Capsule().fill(.white).padding(-2))
                        .offset(x: 6, y: -2)
                }
            Text(tool.name)
                .font(Theme.display(28))
                .foregroundStyle(Theme.ink)
            Text(tool.lesson)
                .font(Theme.body(15, 500))
                .foregroundStyle(Color(hex: 0x4A5841))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 10) {
                Icons.backpack
                    .fill(AngularGradient(colors: HUDButton.rainbowColors, center: .center), style: FillStyle(eoFill: true))
                    .frame(width: 22, height: 22)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white).shadow(color: .black.opacity(0.15), radius: 1.5, y: 1))
                Text(tool.howToUse)
                    .font(Theme.body(14, 700))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .circular).fill(Color(hex: 0xF3F0E6)))
            Text("Here are \(GameModel.lessonGift) to start. Using a tool on a board means any mystery box you're "
                 + "carrying on it is lost.")
                .font(Theme.body(12, 700))
                .foregroundStyle(Color(hex: 0x8A9682))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: done) { Text("Got it!").bigLabel(alt: false) }
                .buttonStyle(Pressable())
                .padding(.top, 2)
        }
    }
}

extension Tool {
    /// The lesson's explanation: when it helps, then what it does.
    var lesson: String {
        switch self {
        case .owl:
            return "Not sure what to tap next? The Wise Owl puts numbered badges on the next 3 nests to tap, in order."
        case .slot:
            return "Slots filling up? The Extra Slot adds a 6th holding slot for the rest of the board. One per board."
        case .peek:
            return "Only the first few nests of each column show. The Magnifying Glass lets you scroll every column "
                + "to see all the nests waiting, until your next tap."
        case .drop:
            return "Blocks buried deep in the picture? 75 acorns rain down over 5 seconds and knock out the blocks "
                + "they hit."
        case .wand:
            return "Tap any nest, even one deep in a column or sitting in a slot. Its chipmunks fly straight to "
                + "their color, over everything in the way."
        }
    }

    /// Where to find it and how to use it.
    var howToUse: String {
        switch self {
        case .wand:
            return "Open the backpack above the board, tap the Magic Wand, then tap the nest to make magic."
        default:
            return "Open the backpack above the board, tap the \(name), then ✓ to use it."
        }
    }
}
