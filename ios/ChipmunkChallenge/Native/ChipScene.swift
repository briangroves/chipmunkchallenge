import SceneKit
import UIKit
import simd

/// The level-intro and lose scenes (the page's createChipScene). Intro: the chipmunk scampers in, hops onto a stump,
/// grabs an acorn and stuffs it in its cheeks, then chews (looping that bit while the board builds). Lose: a cartoon
/// hunter pops up from a bush, BANG, the chipmunk's eyes turn to X's, stars circle its head, it keels over and fades.
final class ChipScene {
    enum Mode { case intro, lose }
    static let introEnd: Float = 2.9
    /// How far the intro camera is raised, in scene units: the chipmunk shows about 6% lower on screen.
    static let introLift: Float = 0.13
    static let loseEnd: Float = 4.6

    let scene = SCNScene()
    let camera = makeCamera(fov: 34)

    private let W = ToonKit(), K = ToonKit()
    private let STUMP_H: Float = 0.3, STUMP_X: Float = 0, CB: Float = 1.35

    private let stump = TNode(), bush = TNode(), chip = TNode(), body = TNode(), head = TNode(), tail = TNode()
    private var shadow: TNode!, smile: TNode!, mouthO: TNode!
    private var paws: [TNode] = [], cheeks: [TNode] = [], eyes: [TNode] = [], xs: [TNode] = [], balls: [TNode] = []
    private var stars: [TNode] = [], smoke: [TNode] = []
    private let acorn = TNode(), hunter = TNode(), gun = TNode()
    private var flash: TNode!, bang: TNode!

    init() {
        let root = scene.rootNode
        root.addChildNode(camera)
        let C = (brown: UInt32(0xC67B3C), dark: UInt32(0x9C5F2D), cream: UInt32(0xF2DDB6), stripe: UInt32(0x4A2C17), nose: UInt32(0x2B1A10))

        // ---- ground, stump, bush
        let ground = W.mesh(Toon.circle(2.6, 48), 0x9CCC65)
        ground.rx = -.pi / 2
        root.addChildNode(ground)
        root.addChildNode(stump)
        stump.add(W.cyl(0.22, 0.26, STUMP_H, 0x8D5A34, STUMP_H / 2))
        do {
            let top = W.mesh(Toon.cylinder(0.22, 0.22, 0.014, segments: 28), 0xE3B98A)
            top.py = STUMP_H + 0.004
            stump.add(top)
            let ring = W.mesh(Toon.torus(0.13, 0.009, 6, 28), 0xB98250)
            ring.rx = .pi / 2
            ring.py = STUMP_H + 0.012
            stump.add(ring)
        }
        stump.add(W.sph(0.06, 0x6F9A4A, 0.19, 0.03, 0.13, 1.4, 0.7, 1), W.sph(0.05, 0x6F9A4A, -0.2, 0.025, 0.11, 1.3, 0.7, 1))
        stump.pos(STUMP_X, 0, 0)
        root.addChildNode(bush)
        for (x, y, r) in [(Float(0), Float(0.18), Float(0.26)), (-0.22, 0.12, 0.18), (0.22, 0.12, 0.2), (-0.08, 0.32, 0.18), (0.12, 0.3, 0.18)] {
            bush.add(W.sph(r, 0x43A047, x, y, 0, 1, 1, 0.8))
        }

        // ---- chipmunk (faces +x)
        chip.scl(1.35)
        root.addChildNode(chip)
        let sm = Toon.basic(0x203010, linear: true)
        sm.writesToDepthBuffer = false
        shadow = meshNode(Toon.circle(0.26, 32), sm)
        shadow.rx = -.pi / 2
        shadow.opacity = 0.2
        root.addChildNode(shadow)
        chip.add(K.sph(0.05, C.dark, 0.04, 0.025, 0.075, 1.7, 0.55, 1), K.sph(0.05, C.dark, 0.04, 0.025, -0.075, 1.7, 0.55, 1))
        body.pos(0, 0.1, 0)
        chip.add(body)
        body.add(K.sph(0.2, C.brown, 0.08, 0.09, 0, 1.22, 0.95, 0.9))
        body.add(K.sph(0.15, C.cream, 0.17, 0.06, 0, 1.05, 0.9, 0.78, line: nil))
        body.add(K.sph(0.09, C.brown, 0, 0.05, 0.1, 1, 1, 0.7), K.sph(0.09, C.brown, 0, 0.05, -0.1, 1, 1, 0.7))
        for (z, c, w) in [(Float(0), C.stripe, Float(0.42)), (0.055, C.cream, 0.36), (-0.055, C.cream, 0.36), (0.1, C.stripe, 0.32), (-0.1, C.stripe, 0.32)] {
            let s = K.sph(0.11, c, 0.06, 0.255 - abs(z) * 0.55, z, 1.9, 0.16, w * 0.35, line: nil)
            s.rot = [-z * 2.2, 0, -0.08]
            body.add(s)
        }
        paws = [K.sph(0.036, C.dark, 0.25, 0, 0.06), K.sph(0.036, C.dark, 0.25, 0, -0.06)]
        paws.forEach { body.add($0) }
        head.pos(0.3, 0.27, 0)
        head.scl(1.32)
        body.add(head)
        head.add(K.sph(0.13, C.brown, 0, 0, 0, 1.06, 0.95, 0.95))
        cheeks = [K.sph(0.07, C.cream, 0.06, -0.045, 0.07, 1, 1, 0.8, line: nil), K.sph(0.07, C.cream, 0.06, -0.045, -0.07, 1, 1, 0.8, line: nil)]
        cheeks.forEach { head.add($0) }
        head.add(K.sph(0.052, C.cream, 0.115, -0.02, 0, 1.1, 0.9, 0.9, line: nil))
        head.add(K.sph(0.022, C.nose, 0.168, 0, 0, 1, 0.85, 1, line: nil))
        smile = K.mesh(Toon.torus(0.026, 0.0055, 6, 16, arc: .pi), C.nose)
        smile.pos(0.155, -0.045, 0)
        smile.rot = [0, .pi / 2, .pi]
        head.add(smile)
        mouthO = K.sph(0.02, 0x5A1E1E, 0.16, -0.04, 0, 0.6, 1, 1, line: nil)
        mouthO.visible = false
        head.add(mouthO)
        for z: Float in [0.07, -0.07] {
            let e = K.sph(0.042, C.dark, -0.03, 0.12, z, 0.6, 1, 0.9)
            e.rx = z * 3
            head.add(e)
            head.add(K.sph(0.022, 0xE7A7A0, -0.012, 0.12, z * 1.05, 0.4, 0.75, 0.6, line: nil))
        }
        for z: Float in [0.098, -0.098] { head.add(K.sph(0.03, C.stripe, 0.02, 0.05, z, 3, 0.35, 0.4, line: nil)) }
        // eyes: shiny black, and X's for the lose gag
        for z: Float in [0.1, -0.1] {
            let g = TNode()
            g.pos(0.07, 0.045, z)
            g.ry = z > 0 ? 0.55 : .pi - 0.55
            head.add(g)
            let e = K.mesh(Toon.sphere, 0x1B1210)
            e.scl(0.03, 0.034, 0.018)
            g.add(e)
            let hl = K.mesh(Toon.sphere, 0xFFFFFF)
            hl.scl(0.009)
            hl.pos(-0.008, 0.012, 0.016)
            g.add(hl)
            eyes.append(g)
            let x = TNode()
            x.simdPosition = g.simdPosition
            x.rot = g.rot
            x.visible = false
            head.add(x)
            for a: Float in [0.785, -0.785] {
                let bar = K.mesh(Toon.box(0.012, 0.06, 0.012), 0x1B1210)
                bar.rz = a
                x.add(bar)
            }
            xs.append(x)
        }
        tail.pos(-0.14, 0.08, 0)
        body.add(tail)
        for i in 0..<11 {
            let f = Float(i) / 10
            let b = K.sph(0.05 + 0.022 * sin(.pi * f), i > 7 ? 0xB98250 : C.dark, line: 1.09)
            tail.add(b)
            balls.append(b)
        }
        // dizzy stars
        for _ in 0..<3 {
            let m = K.mesh(Toon.star, 0xFDD835)
            m.scl(0.035)
            K.outline(m, 1.12)
            root.addChildNode(m)
            stars.append(m)
        }

        // ---- acorn
        acorn.scl(1.5)
        root.addChildNode(acorn)
        acorn.add(W.sph(0.05, 0xC8873A, 0, 0, 0, 0.9, 1.15, 0.9))
        acorn.add(W.sph(0.055, 0x6D4626, 0, 0.035, 0, 1, 0.6, 1))
        acorn.add(W.cyl(0.008, 0.008, 0.03, 0x6D4626, 0.07, line: false))

        // ---- cartoon hunter behind the bush (faces -x)
        root.addChildNode(hunter)
        hunter.add(W.cyl(0.16, 0.2, 0.5, 0xF57C00, 0.25))
        hunter.add(W.sph(0.15, 0xF1C27D, 0, 0.64, 0))
        hunter.add(W.sph(0.05, 0xE0A96D, -0.14, 0.62, 0, 1.2, 1, 1))
        hunter.add(W.sph(0.018, 0x1B1210, -0.11, 0.69, 0.06, line: nil), W.sph(0.018, 0x1B1210, -0.11, 0.69, -0.06, line: nil))
        hunter.add(W.sph(0.06, 0x6D4C41, -0.1, 0.57, 0, 1.6, 0.5, 1.4))
        let hat = TNode()
        hat.py = 0.76
        hunter.add(hat)
        hat.add(W.cyl(0.24, 0.24, 0.025, 0x4A7A3A, 0))
        hat.add(W.cyl(0.12, 0.15, 0.14, 0x4A7A3A, 0.08))
        let feather = W.cyl(0.005, 0.005, 0.2, 0xE53935, 0.12, line: false)
        feather.rz = -0.6
        hat.add(feather)
        gun.pos(-0.12, 0.42, 0.12)
        hunter.add(gun)
        do {
            let barrel = W.cyl(0.022, 0.022, 0.7, 0x78909C, 0)
            barrel.rz = .pi / 2
            barrel.px = -0.3
            gun.add(barrel)
            let stock = W.mesh(Toon.box(0.22, 0.07, 0.05), 0x6D4626)
            stock.px = 0.08
            W.outline(stock, 1.1)
            gun.add(stock)
            gun.add(W.sph(0.04, 0xF1C27D, -0.05, 0, 0), W.sph(0.04, 0xF1C27D, 0.05, -0.02, 0))
        }
        flash = meshNode(Toon.star, Toon.basic(0xFFF176))
        root.addChildNode(flash)
        for _ in 0..<4 {
            let m = W.mesh(Toon.sphere, 0xECEFF1)
            root.addChildNode(m)
            smoke.append(m)
        }
        bang = ChipScene.bangSprite()
        root.addChildNode(bang)
    }

    /// The "BANG!" sign, drawn like the page's 256×128 canvas, on a sprite that always faces the camera.
    private static func bangSprite() -> TNode {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 128), format: {
            let f = UIGraphicsImageRendererFormat()
            f.scale = 1
            f.opaque = false
            return f
        }()).image { ctx in
            let g = ctx.cgContext
            g.setFillColor(UIColor(hex: 0xFFEB3B).cgColor)
            g.setStrokeColor(UIColor(hex: 0xD32F2F).cgColor)
            g.setLineWidth(8)
            for k in 0..<16 {
                let a = CGFloat(k) / 16 * .pi * 2, r: CGFloat = k % 2 == 1 ? 44 : 62
                let p = CGPoint(x: 128 + cos(a) * r * 1.8, y: 64 + sin(a) * r)
                if k == 0 { g.move(to: p) } else { g.addLine(to: p) }
            }
            g.closePath()
            g.drawPath(using: .fillStroke)
            let font = UIFont(name: "LilitaOne", size: 52) ?? .systemFont(ofSize: 52, weight: .black)
            let s = NSAttributedString(string: "BANG!", attributes: [.font: font, .foregroundColor: UIColor(hex: 0xD32F2F)])
            let sz = s.size()
            // textBaseline 'middle': the em box's middle sits at y = 68
            let baseline = 68 + (font.ascender + font.descender) / 2
            s.draw(at: CGPoint(x: 128 - sz.width / 2, y: baseline - font.ascender))
        }
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = brightened(img)
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        let plane = SCNPlane(width: 1, height: 1)
        plane.materials = [m]
        let n = TNode(plane)
        n.constraints = [SCNBillboardConstraint()]
        n.scl(0.62, 0.31, 1)
        return n
    }

    /// The page's CanvasTexture has no sRGB encoding set, so three.js treats its colors as linear and encodes them
    /// on output: the sign comes out lighter than drawn. Same here.
    private static func brightened(_ img: UIImage) -> UIImage {
        guard let cg = img.cgImage else { return img }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var lut = [UInt8](repeating: 0, count: 256)
        for v in 0..<256 { lut[v] = UInt8(min(255, (Toon.encode(CGFloat(v) / 255) * 255).rounded())) }
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = Int(px[i + 3])
            guard a > 0 else { continue }
            for k in 0..<3 {
                let c = min(255, Int(px[i + k]) * 255 / a)
                px[i + k] = UInt8(Int(lut[c]) * a / 255)
            }
        }
        guard let out = ctx.makeImage() else { return img }
        return UIImage(cgImage: out)
    }

    private func layTail(_ curl: Float, _ wig: Float) {
        for (i, b) in balls.enumerated() {
            let f = Float(i) / 10, a = f * (1.1 + curl) + wig * sin(f * 3)
            b.pos(-0.05 * f - 0.13 * sin(a * 0.9), 0.42 * f * (1 - 0.2 * curl) + 0.03 * sin(a), 0.04 * wig * sin(f * 5))
        }
    }

    /// Shared opening: scamper in from the left with squash and stretch, crouch, leap onto the stump, splat, settle.
    private func scamper(_ t: Float) {
        typealias A = Anim
        let run = t < 0.85, ren = A.ease(A.seg(t, 0, 0.85)), ph = sin(t * 15), hp = abs(ph)
        let crouch = sin(.pi * A.seg(t, 0.85, 1.0)), jx = A.seg(t, 1.0, 1.32), air = jx > 0 && jx < 1
        var sy: Float = 1, sxz: Float = 1
        if run { sy = 1 + 0.2 * (hp - 0.45); sxz = 1 - 0.12 * (hp - 0.45) }
        else if t < 1.0 { sy = 1 - 0.24 * crouch; sxz = 1 + 0.16 * crouch }
        else if air { sy = 1 + 0.22 * sin(.pi * jx); sxz = 1 - 0.12 * sin(.pi * jx) }
        else { let u = t - 1.32; sy = 1 - A.spring(u, 0.28, 6, 22); sxz = 1 + A.spring(u, 0.18, 6, 22) }
        let x = -2.3 + (STUMP_X - 0.75 + 2.3) * ren + 0.75 * A.inOut(jx) - 0.06
        let y = jx > 0 ? STUMP_H * A.ease(jx) + sin(.pi * jx) * 0.32 : (run ? hp * 0.07 : 0)
        chip.pos(x, y, 0)
        chip.rot = [0, 0, 0]
        chip.scl(CB * sxz, CB * sy, CB * sxz)
        body.rz = run ? ph * 0.06 : 0
        head.rot = [0, 0, 0]
        layTail(0.15, run ? 0.35 * sin(t * 14) : A.spring(t - 1.32, 0.6, 5, 14) + 0.2 * sin(t * 4))
        shadow.pos(x + 0.05, t > 1.2 ? STUMP_H + 0.016 : 0.003, 0)
        shadow.scl(max(0.5, 1 - (y - (t > 1.2 ? STUMP_H : 0)) * 2))
    }

    private func reset() {
        eyes.forEach { $0.visible = true }
        xs.forEach { $0.visible = false }
        stars.forEach { $0.visible = false }
        cheeks.forEach { $0.scl(0.07, 0.07, 0.056) }
        smile.visible = true
        mouthO.visible = false
        chip.opacity = 1
        for (i, p) in paws.enumerated() { p.pos(0.25, 0, i == 1 ? -0.06 : 0.06) }
        acorn.visible = false; hunter.visible = false; bush.visible = false; flash.visible = false; bang.visible = false
        smoke.forEach { $0.visible = false }
        body.rot = [0, 0, 0]
        shadow.opacity = 0.2
    }

    private func blink(_ t: Float, _ at: Float) {
        let b = sin(.pi * Anim.seg(t, at, at + 0.14))
        eyes.forEach { $0.scl(1, 1 - 0.9 * b, 1) }
    }

    func resize(_ w: CGFloat, _ h: CGFloat) {
        camera.camera?.fieldOfView = w / h < 1 ? 42 : 34
    }

    func setTime(_ mode: Mode, _ t: Float) {
        mode == .intro ? setIntro(t) : setLose(t)
    }

    // MARK: Intro: grab the acorn and stuff it in

    private func setIntro(_ t: Float) {
        typealias A = Anim
        reset()
        // Raised a little (camera and target together), so the chipmunk sits lower in the frame, clear of the title.
        camera.simdPosition = [-0.05, 0.95 + ChipScene.introLift, 2.9]
        camera.simdLook(at: [-0.1, 0.42 + ChipScene.introLift, 0])
        let tt = t > ChipScene.introEnd ? 2.3 + fmod(t - 2.3, 0.6) : t      // keep chewing while the board builds
        scamper(min(tt, 1.9))
        acorn.visible = true
        let sit = A.seg(tt, 1.4, 1.62)
        body.rz = 0.35 * A.inOut(sit)
        head.rz = -0.2 * A.inOut(sit)
        let grab = A.seg(tt, 1.55, 1.8), stuff = A.seg(tt, 1.8, 2.1)
        let hw = head.world
        let restP = SIMD3<Float>(STUMP_X + 0.14, STUMP_H + 0.08, 0.12)
        let pawP = SIMD3<Float>(hw.x + 0.06, hw.y - 0.2, 0.2), mouthP = SIMD3<Float>(hw.x + 0.2, hw.y - 0.04, 0.18)
        for (i, p) in paws.enumerated() { p.pos(0.25 + 0.03 * grab, 0.12 * grab, i == 1 ? -0.05 : 0.05) }
        acorn.simdPosition = stuff <= 0 ? simd_mix(restP, pawP, SIMD3(repeating: A.inOut(grab))) : simd_mix(pawP, mouthP, SIMD3(repeating: A.inOut(stuff)))
        acorn.scl(1.5 * (stuff > 0.7 ? max(0, 1 - (stuff - 0.7) / 0.3) : 1))
        acorn.visible = stuff < 1
        acorn.rz = grab * 2
        let puff = A.back(A.seg(tt, 2.0, 2.25))
        let chew: Float = tt > 2.25 ? abs(sin((tt - 2.25) * 14)) : 0
        for c in cheeks {
            let s = 0.07 * (1 + 0.5 * puff + 0.08 * chew)
            c.scl(s, s, s * 0.8)
        }
        smile.visible = tt < 1.8 || tt > 2.25
        mouthO.visible = tt >= 1.85 && tt <= 2.1
        if tt > 2.25 {
            chip.py += 0.012 * chew
            layTail(0.25, 0.25 * sin(tt * 10))
        }
        blink(tt, 2.55)
    }

    // MARK: Lose: the hunter gag

    private func setLose(_ t: Float) {
        typealias A = Anim
        reset()
        camera.simdPosition = [0.6, 1.0, 3.9]
        camera.simdLook(at: [0.55, 0.45, 0])
        scamper(min(t, 1.9))
        bush.visible = true; hunter.visible = true
        bush.pos(1.55, 0, -0.05)
        let look = A.seg(t, 1.45, 1.85)
        head.ry = -0.5 * sin(.pi * look)
        let rise = A.back(A.seg(t, 1.4, 1.75))
        hunter.pos(1.62, -0.55 + 0.55 * rise, -0.12)
        hunter.rz = 0
        let recoil: Float = t >= 2.05 ? A.spring(t - 2.05, 0.25, 6, 18) : 0
        gun.rz = recoil
        hunter.px += max(0, recoil) * 0.1
        // BANG
        let muzzle = SIMD3<Float>(hunter.px - 0.12 - 0.62, hunter.py + 0.42, 0.12)
        flash.visible = t >= 2.05 && t < 2.3
        flash.simdPosition = muzzle
        flash.scl(0.08 + 0.12 * sin(.pi * A.seg(t, 2.05, 2.3)))
        flash.simdLook(at: camera.simdPosition, up: [0, 1, 0], localFront: [0, 0, 1])
        bang.visible = t >= 2.05 && t < 3.0
        bang.pos(muzzle.x + 0.12, muzzle.y + 0.42, 0.45)
        let bb = A.back(A.seg(t, 2.05, 2.25))
        bang.scl(0.62 * bb, 0.31 * bb, 1)
        bang.opacity = CGFloat(1 - A.seg(t, 2.75, 3.0))
        for (i, s) in smoke.enumerated() {
            let fi = Float(i)
            let u = A.seg(t, 2.08 + fi * 0.05, 3.1)
            s.visible = u > 0 && u < 1
            s.pos(muzzle.x + 0.04 * fi - 0.05, muzzle.y + 0.04 + u * 0.35, 0.1 + fi * 0.02)
            s.scl(0.04 + 0.09 * u)
            s.opacity = CGFloat(0.9 * (1 - u))
        }
        // the chipmunk: startled jump, X eyes, dizzy stars, slow keel-over, fade away
        let jump = sin(.pi * A.seg(t, 2.08, 2.4))
        chip.py += 0.22 * jump
        if jump > 0 {
            let k = 1 + 0.25 * jump
            chip.scl(CB / sqrt(k), CB * k, CB / sqrt(k))
        }
        let dead = t >= 2.12
        eyes.forEach { $0.visible = !dead }
        xs.forEach { $0.visible = dead }
        smile.visible = !dead
        mouthO.visible = dead
        let fall = A.inOut(A.seg(t, 2.6, 3.4))
        chip.rz = -1.45 * fall
        chip.py += 0.06 * fall
        chip.px += 0.05 * fall
        if dead {
            layTail(0.1, 0)
            for (i, p) in paws.enumerated() { p.pos(0.27, 0.05, i == 1 ? -0.08 : 0.08) }
        }
        let hp = head.world
        for (i, s) in stars.enumerated() {
            s.visible = t > 2.3
            let a = t * 5 + Float(i) * 2.09
            s.pos(hp.x + cos(a) * 0.16, hp.y + 0.18 + sin(a * 2) * 0.02, sin(a) * 0.16)
            s.rz = t * 4
        }
        let fade = 1 - A.seg(t, 3.5, 4.4)
        chip.opacity = CGFloat(fade)
        stars.forEach { $0.visible = $0.visible && fade > 0.02; $0.opacity = CGFloat(fade) }
        shadow.opacity = CGFloat(0.2 * fade)
    }
}
