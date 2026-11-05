import SceneKit
import UIKit
import simd

/// The win scene (the page's createKissScene): a chipmunk scampers in and hops onto a stump, a doe trots in, they
/// kiss, little hearts burst out, their heart eyes turn red and pulse, and coins burst up. Same models and timeline.
final class KissScene {
    static let end: Float = 4.6
    static let fade: Double = 0.6

    let scene = SCNScene()
    let camera = makeCamera(fov: 32)

    private let K = ToonKit()
    private let pinkEye = Toon.material(0xFF6FA8, emissive: 0x5A0025)
    private let redEye = Toon.material(0xE8202A, emissive: 0x6A0000)

    private let chip = TNode(), cBody = TNode(), cHead = TNode(), cTail = TNode()
    private var cPawL: TNode!, cPawR: TNode!, cNose: TNode!, cSmile: TNode!, cPucker: TNode!
    private var cBlush: [TNode] = [], chipEyes: [TNode] = [], tailBalls: [TNode] = []
    private let stump = TNode()
    private var chipShadow: TNode!, doeShadow: TNode!
    private let doe = TNode(), dBody = TNode(), dTail = TNode(), neck = TNode(), dHead = TNode()
    private var dNose: TNode!, dSmile: TNode!, dPucker: TNode!
    private var dBlush: [TNode] = [], doeEyes: [TNode] = []
    private struct Leg { let hip: TNode; let knee: TNode; let front: Bool; let side: Float }
    private var legs: [Leg] = []
    private struct Pop { let m: TNode; let a: Float }
    private var pops: [Pop] = []
    private struct Coin { let m: TNode; let delay, vx, vy, vz, spin: Float }
    private var coins: [Coin] = []

    private let STUMP_H: Float = 0.26
    private let CHIP_X: Float = -0.38
    private let NECK0: Float = 0.42
    private let CB: Float = 1.3
    private var KISS_BEND: Float = 0
    private var DOE_KISS_X: Float = 0
    private var KISS_POINT = SIMD3<Float>(0, 0, 0)

    init() {
        camera.simdPosition = [0.3, 1.0, 3.9]
        camera.simdLook(at: [0.22, 0.66, 0])
        scene.rootNode.addChildNode(camera)
        let root = scene.rootNode
        let C = (brown: UInt32(0xC67B3C), dark: UInt32(0x9C5F2D), cream: UInt32(0xF2DDB6), stripe: UInt32(0x4A2C17), nose: UInt32(0x2B1A10))

        func heart(_ size: Float, _ mat: SCNMaterial) -> TNode {
            let m = meshNode(Toon.heart, mat)
            m.scl(size)
            let o = meshNode(Toon.heart, K.line)
            o.scl(1.12)
            m.addChildNode(o)
            return m
        }

        // ---- chipmunk (faces +x)
        chip.scl(1.3)
        root.addChildNode(chip)
        root.addChildNode(stump)
        stump.add(K.cyl(0.2, 0.23, STUMP_H, 0x8D5A34, STUMP_H / 2))
        do {
            let top = K.mesh(Toon.cylinder(0.2, 0.2, 0.012, segments: 28), 0xE3B98A)
            top.py = STUMP_H + 0.003
            stump.add(top)
            let ring = K.mesh(Toon.torus(0.12, 0.008, 6, 28), 0xB98250)
            ring.rx = .pi / 2
            ring.py = STUMP_H + 0.011
            stump.add(ring)
        }
        stump.add(K.sph(0.05, 0x6F9A4A, 0.16, 0.03, 0.12, 1.4, 0.7, 1), K.sph(0.04, 0x6F9A4A, -0.17, 0.025, 0.1, 1.3, 0.7, 1))
        chipShadow = shadowDisc(0.24, 32, opacity: 0.18)
        chipShadow.py = 0.002
        root.addChildNode(chipShadow)
        chip.add(K.sph(0.05, C.dark, 0.04, 0.025, 0.075, 1.7, 0.55, 1), K.sph(0.05, C.dark, 0.04, 0.025, -0.075, 1.7, 0.55, 1))
        cBody.pos(0, 0.1, 0)
        chip.add(cBody)
        cBody.add(K.sph(0.2, C.brown, 0.08, 0.09, 0, 1.22, 0.95, 0.9))
        cBody.add(K.sph(0.15, C.cream, 0.17, 0.06, 0, 1.05, 0.9, 0.78, line: nil))
        cBody.add(K.sph(0.09, C.brown, 0, 0.05, 0.1, 1, 1, 0.7), K.sph(0.09, C.brown, 0, 0.05, -0.1, 1, 1, 0.7))
        for (z, c, w) in [(Float(0), C.stripe, Float(0.42)), (0.055, C.cream, 0.36), (-0.055, C.cream, 0.36), (0.1, C.stripe, 0.32), (-0.1, C.stripe, 0.32)] {
            let s = K.sph(0.11, c, 0.06, 0.255 - abs(z) * 0.55, z, 1.9, 0.16, w * 0.35, line: nil)
            s.rot = [-z * 2.2, 0, -0.08]
            cBody.add(s)
        }
        cPawL = K.sph(0.036, C.dark, 0.25, 0, 0.06)
        cPawR = K.sph(0.036, C.dark, 0.25, 0, -0.06)
        cBody.add(cPawL, cPawR)
        cHead.pos(0.3, 0.27, 0)
        cHead.scl(1.32)
        cBody.add(cHead)
        cHead.add(K.sph(0.13, C.brown, 0, 0, 0, 1.06, 0.95, 0.95))
        cHead.add(K.sph(0.07, C.cream, 0.06, -0.045, 0.07, 1, 1, 0.8, line: nil), K.sph(0.07, C.cream, 0.06, -0.045, -0.07, 1, 1, 0.8, line: nil))
        cHead.add(K.sph(0.052, C.cream, 0.115, -0.02, 0, 1.1, 0.9, 0.9, line: nil))
        cNose = K.sph(0.022, C.nose, 0.168, 0, 0, 1, 0.85, 1, line: nil)
        cHead.add(cNose)
        let SMILE = Toon.torus(0.026, 0.0055, 6, 16, arc: .pi)
        cSmile = K.mesh(SMILE, C.nose)
        cSmile.pos(0.155, -0.045, 0)
        cSmile.rot = [0, .pi / 2, .pi]
        cHead.add(cSmile)
        cPucker = K.sph(0.02, 0xC2185B, 0.17, -0.035, 0, 0.8, 1, 1, line: nil)
        cPucker.visible = false
        cHead.add(cPucker)
        let blushMat = Toon.basic(0xFF7AA2)
        blushMat.writesToDepthBuffer = false
        for z: Float in [0.105, -0.105] {
            let b = meshNode(Toon.sphere, blushMat)
            b.scl(0.03, 0.018, 0.006)
            b.pos(0.09, -0.03, z)
            b.ry = z > 0 ? 0.5 : -0.5
            b.opacity = 0
            cHead.add(b)
            cBlush.append(b)
        }
        for z: Float in [0.07, -0.07] {
            let e = K.sph(0.042, C.dark, -0.03, 0.12, z, 0.6, 1, 0.9)
            e.rx = z * 3
            cHead.add(e)
            cHead.add(K.sph(0.022, 0xE7A7A0, -0.012, 0.12, z * 1.05, 0.4, 0.75, 0.6, line: nil))
        }
        for z: Float in [0.098, -0.098] { cHead.add(K.sph(0.03, C.stripe, 0.02, 0.05, z, 3, 0.35, 0.4, line: nil)) }
        for z: Float in [0.1, -0.1] {
            let h = heart(0.06, pinkEye)
            h.pos(0.07, 0.045, z)
            h.ry = z > 0 ? 0.55 : .pi - 0.55
            cHead.add(h)
            chipEyes.append(h)
        }
        cTail.pos(-0.14, 0.08, 0)
        cBody.add(cTail)
        for i in 0..<11 {
            let f = Float(i) / 10
            let b = K.sph(0.05 + 0.022 * sin(.pi * f), i > 7 ? 0xB98250 : C.dark, line: 1.09)
            cTail.add(b)
            tailBalls.append(b)
        }
        layTail(0, 0)

        // ---- doe (faces -x)
        let D = (coat: UInt32(0xC8955E), light: UInt32(0xEED7B6), muzzle: UInt32(0xDDB386), dark: UInt32(0xA8733F),
                 hoof: UInt32(0x3B2618), nose: UInt32(0x2B1A10), pink: UInt32(0xF5A3B7))
        root.addChildNode(doe)
        doeShadow = shadowDisc(0.62, 40, opacity: 0.16)
        doeShadow.scl(1, 0.45, 1)
        doeShadow.py = 0.002
        root.addChildNode(doeShadow)
        doe.add(dBody)
        dBody.add(K.sph(0.27, D.coat, 0, 0.98, 0, 1.55, 0.78, 0.74))
        dBody.add(K.sph(0.22, D.light, 0, 0.9, 0, 1.45, 0.5, 0.66, line: nil))
        dBody.add(K.sph(0.19, D.coat, -0.3, 1.0, 0, 1, 1.08, 0.92))
        dBody.add(K.sph(0.2, D.coat, 0.29, 1.0, 0, 1, 1, 0.92))
        dTail.pos(0.48, 1.1, 0)
        dBody.add(dTail)
        dTail.add(K.sph(0.075, 0xFBF5EE, 0.02, 0, 0, 0.8, 1.35, 0.8))
        for (x, z) in [(Float(-0.3), Float(0.1)), (-0.28, -0.1), (0.3, 0.1), (0.32, -0.1)] {
            let hip = TNode()
            hip.pos(x, 0.88, z)
            dBody.add(hip)
            hip.add(K.cyl(0.05, 0.036, 0.42, D.coat, -0.21))
            let knee = TNode()
            knee.py = -0.42
            hip.add(knee)
            knee.add(K.cyl(0.032, 0.026, 0.4, D.dark, -0.2))
            knee.add(K.cyl(0.03, 0.036, 0.07, D.hoof, -0.42, line: false))
            legs.append(Leg(hip: hip, knee: knee, front: x < 0, side: z > 0 ? 1 : -1))
        }
        neck.pos(-0.36, 1.08, 0)
        dBody.add(neck)
        neck.add(K.cyl(0.065, 0.1, 0.4, D.coat, 0.18))
        neck.add(K.sph(0.06, D.light, -0.03, 0.16, 0, 0.55, 2.3, 0.85, line: nil))
        dHead.pos(0, 0.4, 0)
        dHead.scl(1.28)
        neck.add(dHead)
        dHead.add(K.sph(0.13, D.coat, 0, 0, 0, 1.15, 0.95, 0.92))
        dHead.add(K.sph(0.085, D.muzzle, -0.15, -0.05, 0, 1.25, 0.8, 0.82))
        dNose = K.sph(0.034, D.nose, -0.25, -0.035, 0, 1, 0.8, 1.1, line: nil)
        dHead.add(dNose)
        dSmile = K.mesh(SMILE, D.nose)
        dSmile.pos(-0.215, -0.09, 0)
        dSmile.rot = [0, .pi / 2, .pi + 0.25]
        dSmile.scl(1.2)
        dHead.add(dSmile)
        dPucker = K.sph(0.024, 0xC2185B, -0.25, -0.085, 0, 0.8, 1, 1, line: nil)
        dPucker.visible = false
        dHead.add(dPucker)
        for z: Float in [0.1, -0.1] {
            let b = meshNode(Toon.sphere, blushMat)
            b.scl(0.036, 0.02, 0.006)
            b.pos(-0.1, -0.04, z)
            b.ry = z > 0 ? -0.4 : 0.4
            b.opacity = 0
            dHead.add(b)
            dBlush.append(b)
        }
        for z: Float in [0.1, -0.1] {
            let g = TNode()
            g.pos(0.06, 0.1, z)
            g.rot = [z > 0 ? -1.05 : 1.05, 0, 0.25]
            dHead.add(g)
            g.add(K.sph(0.075, D.dark, 0, 0.09, 0, 0.5, 1.25, 0.9))
            g.add(K.sph(0.045, D.pink, -0.012, 0.095, z > 0 ? 0.02 : -0.02, 0.42, 1.05, 0.5, line: nil))
        }
        for z: Float in [0.105, -0.105] {
            let h = heart(0.066, pinkEye)
            h.pos(-0.055, 0.035, z)
            h.ry = z > 0 ? -0.45 : .pi + 0.45
            dHead.add(h)
            doeEyes.append(h)
            for k in 0..<3 {
                let l = K.mesh(Toon.box(0.006, 0.032, 0.006), D.nose)
                l.pos(-0.085 + Float(k) * 0.024, 0.085, z * 1.03)
                l.rz = Float(k - 1) * 0.45
                dHead.add(l)
            }
        }
        let flower = TNode()
        flower.pos(0.02, 0.12, 0.12)
        dHead.add(flower)
        for k in 0..<5 {
            let a = Float(k) / 5 * .pi * 2
            flower.add(K.sph(0.022, 0xF48FB1, cos(a) * 0.026, sin(a) * 0.026, 0, 1, 1, 0.6, line: nil))
        }
        flower.add(K.sph(0.016, 0xFFD54F, 0, 0, 0.008, 1, 1, 0.7, line: nil))

        // ---- kiss pop + coins
        for i in 0..<7 {
            let m = meshNode(Toon.heart, Toon.material(i % 2 == 1 ? 0xFF6FA8 : 0xE8202A, emissive: 0x5A0025))
            m.visible = false
            root.addChildNode(m)
            pops.append(Pop(m: m, a: -.pi * 0.15 + Float(i) / 6 * .pi * 1.3))
        }
        let coinFace = Toon.material(0xFFC928, emissive: 0x5A3A00, shader: Toon.metalShader)
        let rimMat = Toon.material(0xD08A00, shader: Toon.metalShader)
        for i in 0..<34 {
            let m = TNode()
            let disc = meshNode(Toon.cylinder(0.055, 0.055, 0.014, segments: 28), coinFace)
            disc.rx = .pi / 2
            m.add(disc)
            m.add(meshNode(Toon.torus(0.055, 0.008, 8, 28), rimMat))
            func r(_ k: Double) -> Float {
                let x = sin(Double(i) * 12.9898 + k * 78.233) * 43758.5453
                return Float(x - floor(x))
            }
            coins.append(Coin(m: m, delay: r(1) * 0.9, vx: -0.5 + r(2) * 1.6, vy: 2.6 + r(3) * 1.4, vz: (r(4) - 0.5) * 0.6, spin: 6 + r(5) * 8))
            root.addChildNode(m)
        }

        // ---- solve the kiss once: chipmunk fully reared at its mark; bend the doe's neck until the noses are level
        stump.pos(CHIP_X + 0.02, 0, 0)
        chip.pos(CHIP_X, STUMP_H, 0)
        chipPose(1)
        let cn = cNose.world
        doe.pos(0, 0, 0)
        var lo: Float = 0, hi: Float = 1.8
        for _ in 0..<30 {
            let mid = (lo + hi) / 2
            doePose(mid)
            if dNose.world.y > cn.y + 0.005 { lo = mid } else { hi = mid }
        }
        KISS_BEND = (lo + hi) / 2
        doePose(KISS_BEND)
        DOE_KISS_X = cn.x + 0.035 - dNose.world.x
        KISS_POINT = [cn.x + 0.02, cn.y + 0.02, 0]
    }

    private func shadowDisc(_ r: Float, _ segs: Int, opacity: CGFloat) -> TNode {
        let m = Toon.basic(0x203010, linear: true)
        m.writesToDepthBuffer = false
        let n = meshNode(Toon.circle(r, segs), m)
        n.rx = -.pi / 2
        n.opacity = opacity
        return n
    }

    private func layTail(_ curl: Float, _ wig: Float) {
        for (i, b) in tailBalls.enumerated() {
            let f = Float(i) / 10
            let a = f * (1.1 + curl) + wig * sin(f * 3)
            b.pos(-0.05 * f - 0.13 * sin(a * 0.9), 0.42 * f * (1 - 0.2 * curl) + 0.03 * sin(a), 0.04 * wig * sin(f * 5))
        }
    }

    private func chipPose(_ rear: Float) {
        cBody.rz = 0.95 * rear
        cHead.rz = -0.62 * rear
        cTail.rz = -0.85 * rear
        cPawL.pos(0.25 - 0.04 * rear, 0.05 * rear, 0.06)
        cPawR.pos(0.25 - 0.04 * rear, 0.05 * rear, -0.06)
    }

    private func doePose(_ bend: Float) {
        neck.rz = NECK0 + bend
        dHead.rz = -NECK0 - bend * 0.62
    }

    func resize(_ w: CGFloat, _ h: CGFloat) {
        camera.camera?.fieldOfView = w / h < 1.1 ? 40 : 32
    }

    func setTime(_ t: Float) {
        typealias A = Anim
        // ---- chipmunk: scamper with squash and stretch, crouch, leap onto the stump, splat landing, springy settle
        let run = t < 0.85, ren = A.ease(A.seg(t, 0, 0.85)), ph = sin(t * 15), hp = abs(ph)
        let crouch = sin(.pi * A.seg(t, 0.85, 1.0)), jx = A.seg(t, 1.0, 1.32), air = jx > 0 && jx < 1
        var sy: Float = 1, sxz: Float = 1
        if run { sy = 1 + 0.2 * (hp - 0.45); sxz = 1 - 0.12 * (hp - 0.45) }
        else if t < 1.0 { sy = 1 - 0.24 * crouch; sxz = 1 + 0.16 * crouch }
        else if air { sy = 1 + 0.22 * sin(.pi * jx); sxz = 1 - 0.12 * sin(.pi * jx) }
        else { let u = t - 1.32; sy = 1 - A.spring(u, 0.28, 6, 22); sxz = 1 + A.spring(u, 0.18, 6, 22) }
        let appr = A.back(A.seg(t, 1.78, 2.22)), part = A.inOut(A.seg(t, 3.35, 3.9))
        let happy = A.seg(t, 3.05, 3.45), hh = sin(.pi * happy)
        if happy > 0 && happy < 1 { sy *= 1 + 0.18 * hh; sxz *= 1 - 0.1 * hh }
        else if t >= 3.45 { sy *= 1 - A.spring(t - 3.45, 0.18, 7, 24); sxz *= 1 + A.spring(t - 3.45, 0.12, 7, 24) }
        let windup = sin(.pi * A.seg(t, 1.6, 1.78))
        let jump = sin(.pi * jx) * 0.3, onTop = STUMP_H * A.ease(jx)
        chip.pos(-2.4 + (CHIP_X - 0.8 + 2.4) * ren + 0.8 * A.inOut(jx), jx > 0 ? onTop + jump + hh * 0.12 : (run ? hp * 0.07 : 0), 0)
        chip.scl(CB * sxz, CB * sy, CB * sxz)
        let rear = min(1.04, appr) * (1 - 0.25 * part)
        chipPose(rear - 0.18 * windup)
        cBody.rz += run ? ph * 0.06 : 0
        // ---- doe: trot in, skid to a stop with a springy lean, wind up, then bend in for the kiss
        let en = A.ease(A.seg(t, 0, 1.3))
        let walking = t < 1.3 || (t > 1.78 && t < 2.22)
        let g = t * 9.5
        doe.pos(2.9 + (DOE_KISS_X + 0.28 - 2.9) * en - 0.28 * min(1, appr) + 0.12 * part, 0, 0)
        for L in legs {
            let p: Float = (L.front ? 0 : .pi) + (L.side > 0 ? 0 : .pi * 0.5)
            let amp: Float = walking ? (t < 1.3 ? 0.45 * (1 - A.seg(t, 1.05, 1.3)) : 0.22) : 0
            L.hip.rz = sin(g + p) * amp
            L.knee.rz = max(0, -sin(g + p)) * amp * 1.4
        }
        dBody.py = walking ? abs(sin(g)) * 0.035 : 0
        dBody.rz = t >= 1.3 ? -A.spring(t - 1.3, 0.07, 5, 16) : 0
        let pop = A.inOut(A.seg(t, 2.25, 2.45)) * (1 - A.inOut(A.seg(t, 3.2, 3.5)))
        let bl = legs[3]
        bl.hip.rz += 0.4 * pop
        bl.knee.rz += 1.6 * pop
        doePose(KISS_BEND * min(1.03, appr) * (1 - 0.45 * part) - 0.12 * windup + 0.05 * sin(t * 2) * (1 - min(1, appr)))
        dTail.rz = sin(t * (t > 2.2 && t < 3.6 ? 24 : 6)) * 0.4
        let kissing = t > 2.2 && t < 2.95
        layTail(0.15 + 0.25 * min(1, appr), kissing ? 0.9 * sin(t * 30) : 0.35 * sin(t * 5) + A.spring(t - 1.32, 0.6, 5, 14))
        if t > 1.3 { dBody.py += sin(t * 3.2) * 0.012 * 0.6 }
        // ---- faces: blink, eyes pop big, close for the kiss, open red and pulse
        let blink = max(sin(.pi * A.seg(t, 1.36, 1.5)), sin(.pi * A.seg(t, 3.8, 3.92)))
        let smitten: Float = t >= 1.5 ? 1 + A.spring(t - 1.5, -0.35, 5, 18) + 0.35 * (1 - A.seg(t, 1.5, 1.5)) : 1
        let closed: Float = kissing ? sin(.pi * min(1, A.seg(t, 2.2, 2.95) * 1.15)) : 0
        let red = t >= 2.95
        var es: Float = t < 1.5 ? 1 : t < 1.78 ? smitten * (1 + 0.08 * sin(t * 20)) : 1.12
        if red {
            let u = t - 2.95
            es = 1.25 + A.spring(u, 0.45, 4, 14) + 0.28 * (0.5 - 0.5 * cos(u / 0.46 * .pi * 2)) * (t < 6.0 ? 1 : 0.2)
        }
        let ey = max(0.12, 1 - blink * 0.9 - closed * 0.88)
        for h in chipEyes + doeEyes { h.geometry?.materials = [red ? redEye : pinkEye] }
        chipEyes.forEach { $0.scl(0.06 * es, 0.06 * es * ey, 0.06 * es) }
        doeEyes.forEach { $0.scl(0.066 * es, 0.066 * es * ey, 0.066 * es) }
        // mouths: smiles, then puckers for the kiss
        cSmile.visible = !kissing; dSmile.visible = !kissing
        cPucker.visible = kissing; dPucker.visible = kissing
        let pk = 1 + 0.35 * sin(.pi * A.seg(t, 2.2, 2.95))
        cPucker.scl(0.016 * pk, 0.02 * pk, 0.02 * pk)
        dPucker.scl(0.019 * pk, 0.024 * pk, 0.024 * pk)
        // heads squish against each other at the moment of the kiss
        let squish = sin(.pi * A.seg(t, 2.18, 2.4))
        cHead.scl(1.32 * (1 - 0.08 * squish), 1.32 * (1 + 0.06 * squish), 1.32)
        dHead.scl(1.28 * (1 - 0.06 * squish), 1.28 * (1 + 0.05 * squish), 1.28)
        let blush = CGFloat(0.75 * A.seg(t, 2.3, 2.8))
        (cBlush + dBlush).forEach { $0.opacity = blush }
        // ---- a burst of little hearts from the kiss
        for (i, p) in pops.enumerated() {
            let fi = Float(i)
            let u = A.seg(t, 2.25 + fi * 0.03, 3.25 + fi * 0.03)
            p.m.visible = u > 0 && u < 1
            if !p.m.visible { continue }
            let d = 0.12 + 0.42 * A.ease(u)
            p.m.pos(KISS_POINT.x + cos(p.a) * d * 0.8, KISS_POINT.y + 0.06 + sin(p.a) * d * 0.5 + 0.25 * u, 0.08)
            p.m.scl(0.045 * A.back(min(1, u * 3)) * (1 - 0.3 * u))
            p.m.opacity = CGFloat(1 - A.seg(u, 0.65, 1))
            p.m.rz = sin(u * 8 + fi) * 0.3
        }
        // ---- coins burst up from the kiss and sail off the top
        for c in coins {
            let u = t - 3.0 - c.delay * 0.9
            if u < 0 { c.m.visible = false; continue }
            c.m.visible = true
            c.m.pos(KISS_POINT.x + c.vx * u, KISS_POINT.y + 0.1 + c.vy * u - 0.55 * u * u, 0.1 + c.vz * u)
            c.m.rot = [0, u * c.spin, u * 2]
            c.m.scl(A.back(min(1, u * 4)))
            let a = 1 - A.seg(u, 1.1, 1.6)
            c.m.opacity = CGFloat(a)
            if a <= 0 { c.m.visible = false }
        }
        chipShadow.pos(chip.px + 0.05, chip.py > 0.2 || t > 1.2 ? STUMP_H + 0.014 : 0.002, 0)
        chipShadow.scl(max(0.5, 1 - (chip.py - (t > 1.2 ? STUMP_H : 0)) * 2))
        doeShadow.px = doe.px
    }
}
