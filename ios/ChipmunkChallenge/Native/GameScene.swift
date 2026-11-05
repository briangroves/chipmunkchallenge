import ChipmunkEngine
import SpriteKit
import UIKit

/// Draws one board: the picture as beveled tiles on a wooden tray, the drain, the holding slots, the lanes of nests,
/// and every critter on its way. Each frame it moves the model's clock forward and redraws whatever changed.
final class GameScene: SKScene {
    let model: GameModel

    // Layout (scene points). The navigation grid's top-left corner and cell size.
    private var cs: CGFloat = 8
    private var gridOrigin = CGPoint.zero
    private var slotSize: CGFloat = 56
    private var slotY: CGFloat = 0
    private var nestSize: CGFloat = 56
    private var laneTop: CGFloat = 0
    private var laneXs: [CGFloat] = []
    private var visibleRows = 3

    // Nodes.
    private let world = SKNode()
    private let boardLayer = SKNode()
    private let slotLayer = SKNode()
    private let laneLayer = SKNode()
    private let critterLayer = SKNode()
    private var tiles: [SKSpriteNode?] = []
    private var shown: [UInt8] = []
    private var critters: [Int: CritterNode] = [:]

    private var builtVersion = -1
    private var layoutSize = CGSize.zero
    private var slotSignature = ""
    private var laneSignature = ""
    private var lastTime: TimeInterval?

    init(model: GameModel) {
        self.model = model
        super.init(size: CGSize(width: 390, height: 700))
        scaleMode = .resizeFill
        backgroundColor = Palette.wood
        addChild(world)
        world.addChild(boardLayer)
        world.addChild(slotLayer)
        world.addChild(laneLayer)
        world.addChild(critterLayer)
        boardLayer.zPosition = 1
        critterLayer.zPosition = 5
        slotLayer.zPosition = 3
        laneLayer.zPosition = 3
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime.map { currentTime - $0 } ?? 0
        lastTime = currentTime
        guard let lv = model.level else {
            if builtVersion != -1 { clearBoard() }
            return
        }
        if builtVersion != model.boardVersion || layoutSize != size {
            build(lv)
        }
        model.advance(by: dt, observer: SimObserver())
        guard let m = model.sim else { return }
        syncTiles(m)
        syncSlots(lv, m)
        syncLanes(lv, m)
        syncCritters(lv, m)
    }

    // MARK: - Layout and the static parts

    private func clearBoard() {
        boardLayer.removeAllChildren()
        slotLayer.removeAllChildren()
        laneLayer.removeAllChildren()
        critterLayer.removeAllChildren()
        critters = [:]
        tiles = []
        builtVersion = -1
    }

    private func build(_ lv: Level) {
        clearBoard()
        builtVersion = model.boardVersion
        layoutSize = size
        slotSignature = ""
        laneSignature = ""

        let margin: CGFloat = 12
        let W = size.width, H = size.height
        cs = min((W - 2 * margin) / CGFloat(lv.NW), (H * 0.56) / CGFloat(lv.NH)).rounded(.down)
        cs = max(cs, 4)
        gridOrigin = CGPoint(x: ((W - CGFloat(lv.NW) * cs) / 2).rounded(), y: H - margin)
        let gridBottom = gridOrigin.y - CGFloat(lv.NH) * cs

        slotSize = min(CGFloat(lv.NW) * cs / CGFloat(lv.slots) - 10, 64)
        slotY = gridBottom - 6 - slotSize / 2
        laneTop = slotY - slotSize / 2 - 18
        let lanes = max(1, lv.lanes.count)
        let colW = (W - 2 * margin) / CGFloat(lanes)
        nestSize = min(colW - 14, 64)
        visibleRows = max(1, min(3, Int((laneTop - margin) / (nestSize + 10))))
        if visibleRows < 3 { nestSize = min(nestSize, (laneTop - margin) / 3 - 10); visibleRows = 3 }
        laneXs = (0..<lanes).map { margin + colW * (CGFloat($0) + 0.5) }

        drawPlanks()
        drawFrame(lv)
        drawTiles(lv)
        drawDrain(lv)
    }

    private func drawPlanks() {
        let n = 6
        let w = size.width / CGFloat(n)
        for k in 0..<n {
            let plank = SKShapeNode(rect: CGRect(x: CGFloat(k) * w, y: 0, width: w, height: size.height))
            plank.fillColor = k % 2 == 0 ? Palette.wood : Palette.woodAlt
            plank.strokeColor = Palette.woodLine
            plank.lineWidth = 1
            plank.zPosition = -10
            boardLayer.addChild(plank)
        }
    }

    private func drawFrame(_ lv: Level) {
        let r = CGRect(x: gridOrigin.x + CGFloat(MG.l) * cs, y: gridOrigin.y - CGFloat(MG.t + lv.H) * cs,
                       width: CGFloat(lv.W) * cs, height: CGFloat(lv.H) * cs).insetBy(dx: -cs * 0.6, dy: -cs * 0.6)
        let shadow = SKShapeNode(rect: r.offsetBy(dx: 0, dy: -3), cornerRadius: 6)
        shadow.fillColor = UIColor.black.withAlphaComponent(0.18)
        shadow.strokeColor = .clear
        shadow.zPosition = -2
        boardLayer.addChild(shadow)
        let frame = SKShapeNode(rect: r, cornerRadius: 6)
        frame.fillColor = Palette.frame
        frame.strokeColor = Palette.frameEdge
        frame.lineWidth = 2
        frame.zPosition = -1
        boardLayer.addChild(frame)
    }

    private func drawTiles(_ lv: Level) {
        let n = lv.W * lv.H
        tiles = Array(repeating: nil, count: n)
        shown = lv.art.cells
        let tex = Textures.tile(size: cs * UIScreen.main.scale)
        let rockTex = Textures.rock(size: cs * UIScreen.main.scale)
        for i in 0..<n {
            let v = lv.art.cells[i]
            if v == 0 { continue }
            let node: SKSpriteNode
            if v == ROCK {
                node = SKSpriteNode(texture: rockTex, size: CGSize(width: cs, height: cs))
            } else {
                node = SKSpriteNode(texture: tex, size: CGSize(width: cs, height: cs))
                node.color = UIColor(rgb: lv.rgb(Int(v)))
                node.colorBlendFactor = 1
            }
            node.position = cellPoint(lv.boardToNav(i))
            boardLayer.addChild(node)
            tiles[i] = node
        }
    }

    private func drawDrain(_ lv: Level) {
        let p = cellPoint(lv.drain)
        let rim = SKShapeNode(ellipseOf: CGSize(width: cs * 4.4, height: cs * 2.8))
        rim.fillColor = Palette.drainRim
        rim.strokeColor = .clear
        rim.position = p
        rim.zPosition = 0
        boardLayer.addChild(rim)
        let hole = SKShapeNode(ellipseOf: CGSize(width: cs * 3.6, height: cs * 2.1))
        hole.fillColor = Palette.drain
        hole.strokeColor = .clear
        hole.position = CGPoint(x: p.x, y: p.y - cs * 0.15)
        hole.zPosition = 0.1
        boardLayer.addChild(hole)
    }

    /// Center of navigation cell n.
    private func cellPoint(_ n: Int) -> CGPoint {
        guard let lv = model.level else { return .zero }
        return gridPoint(x: Double(n % lv.NW) + 0.5, y: Double(n / lv.NW) + 0.5)
    }

    private func gridPoint(x: Double, y: Double) -> CGPoint {
        CGPoint(x: gridOrigin.x + CGFloat(x) * cs, y: gridOrigin.y - CGFloat(y) * cs)
    }

    private func slotX(_ lv: Level, _ k: Int) -> CGFloat {
        k < lv.entry.count ? cellPoint(lv.entry[k]).x : size.width / 2
    }

    // MARK: - Per-frame sync

    private func syncTiles(_ m: Sim) {
        for i in 0..<min(shown.count, m.s.b.count) where shown[i] != m.s.b[i] {
            shown[i] = m.s.b[i]
            if m.s.b[i] == 0, let t = tiles[i] {
                tiles[i] = nil
                t.run(.sequence([.group([.scale(to: 0.2, duration: 0.12), .fadeOut(withDuration: 0.12)]),
                                 .removeFromParent()]))
            }
        }
    }

    private func syncSlots(_ lv: Level, _ m: Sim) {
        let sig = "\(lv.slots)|\(m.s.locked)|" + m.s.sl.map { "\($0.k):\($0.c):\($0.r):\($0.key)" }.joined(separator: ",")
        if sig == slotSignature { return }
        slotSignature = sig
        slotLayer.removeAllChildren()
        for k in 0..<lv.slots {
            let x = slotX(lv, k)
            let empty = SKShapeNode(rectOf: CGSize(width: slotSize, height: slotSize), cornerRadius: slotSize * 0.22)
            empty.fillColor = Palette.slot
            empty.strokeColor = Palette.slotEdge
            empty.lineWidth = 1.5
            empty.position = CGPoint(x: x, y: slotY)
            slotLayer.addChild(empty)
            if m.s.locked && k == lv.lockAt {
                let lock = SKLabelNode(text: "🔒")
                lock.fontSize = slotSize * 0.45
                lock.verticalAlignmentMode = .center
                lock.position = empty.position
                slotLayer.addChild(lock)
            }
        }
        for n in m.s.sl {
            let tile = NestNode(color: UIColor(rgb: lv.rgb(n.c)), count: n.r, size: slotSize, key: n.key)
            tile.position = CGPoint(x: slotX(lv, n.k), y: slotY)
            slotLayer.addChild(tile)
        }
    }

    private func syncLanes(_ lv: Level, _ m: Sim) {
        let open = canTap(lv, m.s)
        let sig = "\(open)|" + m.s.lp.map(String.init).joined(separator: ",")
        if sig == laneSignature { return }
        laneSignature = sig
        laneLayer.removeAllChildren()
        for (l, lane) in lv.lanes.enumerated() {
            var shownRows = 0
            var idx = m.s.lp[l]
            while idx < lane.count && shownRows < visibleRows {
                if m.s.tk[l][idx] != 0 { idx += 1; continue }
                let n = lane[idx]
                let tile = NestNode(color: UIColor(rgb: lv.rgb(n.c)), count: n.n, size: nestSize, key: n.key)
                tile.position = CGPoint(x: laneXs[l], y: laneTop - nestSize / 2 - CGFloat(shownRows) * (nestSize + 10))
                if shownRows == 0 {
                    tile.name = "lane-\(l)"
                    if !open { tile.alpha = 0.55 }
                } else {
                    tile.alpha = 0.9
                    tile.setScale(0.92)
                }
                laneLayer.addChild(tile)
                shownRows += 1
                idx += 1
            }
        }
    }

    private func syncCritters(_ lv: Level, _ m: Sim) {
        var live = Set<Int>()
        for a in m.ants {
            live.insert(a.i)
            let node: CritterNode
            if let c = critters[a.i] {
                node = c
            } else {
                node = CritterNode(color: UIColor(rgb: lv.rgb(a.c)), cell: cs)
                critters[a.i] = node
                critterLayer.addChild(node)
            }
            let p = antPose(lv, a, at: model.simT)
            node.position = gridPoint(x: p.x, y: p.y)
            if p.dx != 0 || p.dy != 0 { node.zRotation = atan2(-CGFloat(p.dy), CGFloat(p.dx)) }
            node.carrying = p.carrying
        }
        for (k, node) in critters where !live.contains(k) {
            node.removeFromParent()
            critters[k] = nil
        }
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        for node in nodes(at: p) {
            var n: SKNode? = node
            while let cur = n {
                if let name = cur.name, name.hasPrefix("lane-"), let l = Int(name.dropFirst(5)) {
                    if model.tap(lane: l) {
                        cur.run(.sequence([.scale(to: 0.9, duration: 0.05), .scale(to: 1, duration: 0.08)]))
                    } else {
                        cur.run(.sequence([.moveBy(x: -4, y: 0, duration: 0.04), .moveBy(x: 8, y: 0, duration: 0.06),
                                           .moveBy(x: -4, y: 0, duration: 0.04)]))
                    }
                    return
                }
                n = cur.parent
            }
        }
    }
}

// MARK: - Nodes

/// A nest tile: a rounded block in the nest's color with a darker lip and its critter count.
final class NestNode: SKNode {
    init(color: UIColor, count: Int, size: CGFloat, key: Bool) {
        super.init()
        let lip = SKShapeNode(rectOf: CGSize(width: size, height: size), cornerRadius: size * 0.24)
        lip.fillColor = color.darker(0.28)
        lip.strokeColor = .clear
        lip.position = CGPoint(x: 0, y: -size * 0.07)
        addChild(lip)
        let face = SKShapeNode(rectOf: CGSize(width: size, height: size * 0.94), cornerRadius: size * 0.24)
        face.fillColor = color
        face.strokeColor = color.lighter(0.25)
        face.lineWidth = 2
        face.position = CGPoint(x: 0, y: size * 0.02)
        addChild(face)
        let label = SKLabelNode()
        label.attributedText = NSAttributedString(string: "\(count)", attributes: [
            .font: UIFont.systemFont(ofSize: size * 0.42, weight: .black).rounded,
            .foregroundColor: UIColor.white,
            .strokeColor: UIColor(white: 0.12, alpha: 1),
            .strokeWidth: -5,
        ])
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: size * 0.02)
        addChild(label)
        if key {
            let k = SKLabelNode(text: "🔑")
            k.fontSize = size * 0.3
            k.position = CGPoint(x: size * 0.32, y: size * 0.22)
            k.verticalAlignmentMode = .center
            addChild(k)
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// A critter seen from above: body, head and tail in its nest's color, carrying its block home.
final class CritterNode: SKNode {
    private let block: SKShapeNode

    var carrying = false {
        didSet { if carrying != oldValue { block.isHidden = !carrying } }
    }

    init(color: UIColor, cell: CGFloat) {
        let len = cell * 2.4
        block = SKShapeNode(rectOf: CGSize(width: cell * 1.1, height: cell * 1.1), cornerRadius: cell * 0.2)
        super.init()
        let tail = SKShapeNode(ellipseOf: CGSize(width: len * 0.5, height: len * 0.22))
        tail.fillColor = color.darker(0.2)
        tail.strokeColor = UIColor(white: 0.1, alpha: 0.8)
        tail.lineWidth = 0.8
        tail.position = CGPoint(x: -len * 0.45, y: 0)
        addChild(tail)
        let body = SKShapeNode(ellipseOf: CGSize(width: len * 0.62, height: len * 0.38))
        body.fillColor = color
        body.strokeColor = UIColor(white: 0.1, alpha: 0.85)
        body.lineWidth = 1
        addChild(body)
        let head = SKShapeNode(circleOfRadius: len * 0.16)
        head.fillColor = color.lighter(0.15)
        head.strokeColor = UIColor(white: 0.1, alpha: 0.85)
        head.lineWidth = 1
        head.position = CGPoint(x: len * 0.32, y: 0)
        addChild(head)
        block.fillColor = color.lighter(0.1)
        block.strokeColor = UIColor(white: 0.1, alpha: 0.9)
        block.lineWidth = 1
        block.position = CGPoint(x: len * 0.5, y: 0)
        block.isHidden = true
        addChild(block)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Look

enum Palette {
    static let wood = UIColor(rgb: 0xEFCFA4)
    static let woodAlt = UIColor(rgb: 0xEBC899)
    static let woodLine = UIColor(rgb: 0xDDB585)
    static let frame = UIColor(rgb: 0xD9C3A0)
    static let frameEdge = UIColor(rgb: 0xC4A97F)
    static let drain = UIColor(rgb: 0x2A1A10)
    static let drainRim = UIColor(rgb: 0x8A5A36)
    static let slot = UIColor(rgb: 0xFFF8EE)
    static let slotEdge = UIColor(rgb: 0xE2CDAE)
}

enum Textures {
    /// A white beveled tile; tinted per color with colorBlendFactor.
    static func tile(size px: CGFloat) -> SKTexture {
        let s = max(4, px.rounded())
        let img = UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
            let g = ctx.cgContext
            let r = CGRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.05, dy: s * 0.05)
            g.setFillColor(UIColor(white: 0.72, alpha: 1).cgColor)
            g.addPath(UIBezierPath(roundedRect: r, cornerRadius: s * 0.18).cgPath)
            g.fillPath()
            let face = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.86)
            g.setFillColor(UIColor.white.cgColor)
            g.addPath(UIBezierPath(roundedRect: face, cornerRadius: s * 0.16).cgPath)
            g.fillPath()
            g.setFillColor(UIColor(white: 1, alpha: 1).cgColor)
            let shine = CGRect(x: face.minX + s * 0.14, y: face.minY + s * 0.12, width: s * 0.22, height: s * 0.16)
            g.addPath(UIBezierPath(ovalIn: shine).cgPath)
            g.fillPath()
        }
        let t = SKTexture(image: img)
        t.filteringMode = .linear
        return t
    }

    static func rock(size px: CGFloat) -> SKTexture {
        let s = max(4, px.rounded())
        let img = UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
            let g = ctx.cgContext
            let r = CGRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.02, dy: s * 0.02)
            g.setFillColor(UIColor(rgb: 0x5D5650).cgColor)
            g.addPath(UIBezierPath(roundedRect: r, cornerRadius: s * 0.3).cgPath)
            g.fillPath()
            g.setFillColor(UIColor(rgb: 0x7C746C).cgColor)
            g.addPath(UIBezierPath(roundedRect: r.insetBy(dx: s * 0.12, dy: s * 0.12).offsetBy(dx: 0, dy: -s * 0.06),
                                   cornerRadius: s * 0.25).cgPath)
            g.fillPath()
        }
        return SKTexture(image: img)
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    func darker(_ f: CGFloat) -> UIColor { mix(with: .black, f) }
    func lighter(_ f: CGFloat) -> UIColor { mix(with: .white, f) }

    private func mix(with o: UIColor, _ f: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        o.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r + (r2 - r) * f, green: g + (g2 - g) * f, blue: b + (b2 - b) * f, alpha: a)
    }
}

extension UIFont {
    var rounded: UIFont {
        guard let d = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: d, size: pointSize)
    }
}
