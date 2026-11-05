import SceneKit
import UIKit
import simd

/// A small three.js-style toolkit on top of SceneKit, so the web game's 3D scenes (win, intro, lose) port line for line.
/// Shading matches three.js r128 MeshToonMaterial with the page's lights: a hemisphere light (sky white, ground
/// 0x8aa070, intensity .75) plus a directional light from (2,4,3) at .75, stepped through the 3-texel gradient
/// [90,170,255]. Outlines are inverted hulls, as on the page.

/// A node with a three.js Euler rotation (order XYZ).
final class TNode: SCNNode {
    var rot = SIMD3<Float>(0, 0, 0) {
        didSet { simdOrientation = TNode.quat(rot) }
    }

    static func quat(_ r: SIMD3<Float>) -> simd_quatf {
        simd_quatf(angle: r.x, axis: [1, 0, 0]) * simd_quatf(angle: r.y, axis: [0, 1, 0]) * simd_quatf(angle: r.z, axis: [0, 0, 1])
    }

    func pos(_ x: Float, _ y: Float, _ z: Float) { simdPosition = [x, y, z] }
    func scl(_ x: Float, _ y: Float, _ z: Float) { simdScale = [x, y, z] }
    func scl(_ s: Float) { simdScale = [s, s, s] }
    var px: Float { get { simdPosition.x } set { simdPosition.x = newValue } }
    var py: Float { get { simdPosition.y } set { simdPosition.y = newValue } }
    var pz: Float { get { simdPosition.z } set { simdPosition.z = newValue } }
    var rx: Float { get { rot.x } set { rot.x = newValue } }
    var ry: Float { get { rot.y } set { rot.y = newValue } }
    var rz: Float { get { rot.z } set { rot.z = newValue } }
    var visible: Bool { get { !isHidden } set { isHidden = !newValue } }

    convenience init(_ g: SCNGeometry?) {
        self.init()
        geometry = g
    }

    @discardableResult
    func add(_ nodes: SCNNode...) -> TNode {
        nodes.forEach(addChildNode)
        return self
    }

    var world: SIMD3<Float> { simdWorldPosition }
}

enum Toon {
    /// MeshToonMaterial lighting, written out (three.js r128, non-physical lights).
    // SceneKit runs in gamma space (SCNDisableLinearSpaceRendering), like the page's WebGL: colors arrive as sRGB,
    // lighting is done in linear and encoded back to sRGB in the shader, and blending happens on sRGB values.
    static let shader = """
    #pragma body
    float3 dc = _surface.diffuse.rgb;
    float3 dl = mix(dc / 12.92, pow((dc + 0.055) / 1.055, float3(2.4)), step(float3(0.04045), dc));
    float3 n = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
    float3 L = normalize(float3(2.0, 4.0, 3.0));
    float u = dot(n, L) * 0.5 + 0.5;
    float g = u < (1.0 / 3.0) ? (90.0 / 255.0) : (u < (2.0 / 3.0) ? (170.0 / 255.0) : 1.0);
    float3 hemi = mix(float3(138.0, 160.0, 112.0) / 255.0, float3(1.0), n.y * 0.5 + 0.5);
    float3 c = clamp(dl * (hemi * 0.75 + g * 0.75) + _surface.emission.rgb, 0.0, 1.0);
    c = mix(c * 12.92, 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, step(float3(0.0031308), c));
    _output.color = float4(c, 1.0);
    """

    /// MeshStandardMaterial-ish (the coins): Lambert plus a soft highlight under the same lights.
    static let metalShader = """
    #pragma body
    float3 dc = _surface.diffuse.rgb;
    float3 dl = mix(dc / 12.92, pow((dc + 0.055) / 1.055, float3(2.4)), step(float3(0.04045), dc));
    float3 n = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
    float3 L = normalize(float3(2.0, 4.0, 3.0));
    float3 V = normalize((scn_frame.inverseViewTransform * float4(_surface.view, 0.0)).xyz);
    float d = max(dot(n, L), 0.0);
    float3 H = normalize(L + V);
    float s = pow(max(dot(n, H), 0.0), 40.0) * 0.9;
    float3 hemi = mix(float3(138.0, 160.0, 112.0) / 255.0, float3(1.0), n.y * 0.5 + 0.5);
    float3 c = clamp(dl * (hemi * 0.75 * 0.55 + d * 0.75 * 0.75) + s * dl + _surface.emission.rgb, 0.0, 1.0);
    c = mix(c * 12.92, 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, step(float3(0.0031308), c));
    _output.color = float4(c, 1.0);
    """

    /// sRGB encoding of a linear 0…1 value.
    static func encode(_ v: CGFloat) -> CGFloat { v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }

    /// A color given in three.js without sRGB conversion (linear), as the sRGB color it ends up on screen.
    static func linearColor(_ h: UInt32) -> UIColor {
        UIColor(red: encode(CGFloat((h >> 16) & 255) / 255), green: encode(CGFloat((h >> 8) & 255) / 255),
                blue: encode(CGFloat(h & 255) / 255), alpha: 1)
    }

    static func material(_ hex: UInt32, emissive: UInt32? = nil, shader: String = Toon.shader) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(hex: hex)
        if let e = emissive { m.emission.contents = UIColor(hex: e) }   // raw linear numbers, added in the shader
        m.shaderModifiers = [.fragment: shader]
        return m
    }

    /// MeshBasicMaterial: flat color.
    static func basic(_ hex: UInt32, back: Bool = false, linear: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = linear ? linearColor(hex) : UIColor(hex: hex)
        if back { m.cullMode = .front }
        return m
    }

    // MARK: Geometry (three.js conventions)

    static let sphere: SCNGeometry = {
        let s = SCNSphere(radius: 1)
        s.segmentCount = 32
        return s
    }()

    static func cylinder(_ rt: Float, _ rb: Float, _ h: Float, segments: Int = 20) -> SCNGeometry {
        let c = SCNCone(topRadius: CGFloat(rt), bottomRadius: CGFloat(rb), height: CGFloat(h))
        c.radialSegmentCount = segments
        return c
    }

    /// TorusGeometry(radius, tube, radialSegments, tubularSegments, arc): in the XY plane, around +z.
    static func torus(_ R: Float, _ r: Float, _ radial: Int, _ tubular: Int, arc: Float = 2 * .pi) -> SCNGeometry {
        var v: [SCNVector3] = [], n: [SCNVector3] = [], idx: [Int32] = []
        for j in 0...radial {
            for i in 0...tubular {
                let u = Float(i) / Float(tubular) * arc, a = Float(j) / Float(radial) * 2 * .pi
                let p = SIMD3<Float>((R + r * cos(a)) * cos(u), (R + r * cos(a)) * sin(u), r * sin(a))
                let c = SIMD3<Float>(R * cos(u), R * sin(u), 0)
                let nn = simd_normalize(p - c)
                v.append(SCNVector3(p.x, p.y, p.z))
                n.append(SCNVector3(nn.x, nn.y, nn.z))
            }
        }
        for j in 1...radial {
            for i in 1...tubular {
                let a = Int32((tubular + 1) * j + i - 1), b = Int32((tubular + 1) * (j - 1) + i - 1)
                let c = Int32((tubular + 1) * (j - 1) + i), d = Int32((tubular + 1) * j + i)
                idx += [a, b, d, b, c, d]
            }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: v), SCNGeometrySource(normals: n)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    /// CircleGeometry(radius, segments): a disc in the XY plane facing +z.
    static func circle(_ r: Float, _ segs: Int) -> SCNGeometry {
        var v = [SCNVector3(0, 0, 0)], n = [SCNVector3(0, 0, 1)], idx: [Int32] = []
        for i in 0...segs {
            let a = Float(i) / Float(segs) * 2 * .pi
            v.append(SCNVector3(r * cos(a), r * sin(a), 0))
            n.append(SCNVector3(0, 0, 1))
        }
        for i in 1...segs { idx += [0, Int32(i), Int32(i + 1)] }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: v), SCNGeometrySource(normals: n)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    static func box(_ w: Float, _ h: Float, _ d: Float) -> SCNGeometry {
        SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: 0)
    }

    /// ExtrudeGeometry of a path, centered on its bounding box (geometry.center()).
    static func extrude(_ path: UIBezierPath, depth: CGFloat, chamfer: CGFloat = 0) -> SCNGeometry {
        let r = path.bounds
        path.apply(CGAffineTransform(translationX: -r.midX, y: -r.midY))
        path.flatness = 0.002
        let s = SCNShape(path: path, extrusionDepth: depth)
        s.chamferRadius = chamfer
        return s
    }

    /// The page's heart (eyes and the kiss pop): depth .18 with a .08 bevel each side, growing the outline by .07.
    static let heart: SCNGeometry = {
        let p = UIBezierPath()
        let k: CGFloat = 1.1      // the bevel pushes the outline out by .07 on a ~1.3-wide heart
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
        p.move(to: pt(0, -0.5))
        p.addCurve(to: pt(0, 0.45), controlPoint1: pt(-0.95, 0.1), controlPoint2: pt(-0.6, 0.85))
        p.addCurve(to: pt(0, -0.5), controlPoint1: pt(0.6, 0.85), controlPoint2: pt(0.95, 0.1))
        p.close()
        return extrude(p, depth: 0.34, chamfer: 0.08)
    }()

    /// The dizzy-star / muzzle-flash shape: 10 points alternating radius 1 and .4, extruded .25.
    static let star: SCNGeometry = {
        let p = UIBezierPath()
        for k in 0..<10 {
            let a = CGFloat(k) / 10 * 2 * .pi - .pi / 2, r: CGFloat = k % 2 == 1 ? 0.4 : 1
            let q = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if k == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.close()
        return extrude(p, depth: 0.25)
    }()
}

/// One material set (the page's `kit()`): toon materials by color, the outline material, and the sph/cyl builders.
final class ToonKit {
    private var mats: [UInt32: SCNMaterial] = [:]
    let line = Toon.basic(0x2A1A10, back: true)

    func toon(_ c: UInt32) -> SCNMaterial {
        if let m = mats[c] { return m }
        let m = Toon.material(c)
        mats[c] = m
        return m
    }

    @discardableResult
    func outline(_ m: TNode, _ k: Float = 1.07) -> TNode {
        let g = m.geometry!.copy() as! SCNGeometry
        g.materials = [line]
        let o = TNode(g)
        o.scl(k)
        m.addChildNode(o)
        return m
    }

    /// sph(r, c, x, y, z, sx, sy, sz, line): line nil = no outline.
    func sph(_ r: Float, _ c: UInt32, _ x: Float = 0, _ y: Float = 0, _ z: Float = 0,
             _ sx: Float = 1, _ sy: Float = 1, _ sz: Float = 1, line: Float? = 1.07) -> TNode {
        let g = Toon.sphere.copy() as! SCNGeometry
        g.materials = [toon(c)]
        let m = TNode(g)
        m.scl(r * sx, r * sy, r * sz)
        m.pos(x, y, z)
        if let l = line { outline(m, l) }
        return m
    }

    func cyl(_ rt: Float, _ rb: Float, _ h: Float, _ c: UInt32, _ y: Float = 0, line: Bool = true) -> TNode {
        let g = Toon.cylinder(rt, rb, h)
        g.materials = [toon(c)]
        let m = TNode(g)
        m.py = y
        if line { outline(m, 1.08) }
        return m
    }

    func mesh(_ g: SCNGeometry, _ c: UInt32) -> TNode {
        let g = g.copy() as! SCNGeometry
        g.materials = [toon(c)]
        return TNode(g)
    }
}

/// Mesh with its own material.
func meshNode(_ g: SCNGeometry, _ m: SCNMaterial) -> TNode {
    let g = g.copy() as! SCNGeometry
    g.materials = [m]
    return TNode(g)
}

// MARK: - Timing helpers (the page's ease, inout, seg, back, spring)

enum Anim {
    static func ease(_ t: Float) -> Float { t <= 0 ? 0 : t >= 1 ? 1 : 1 - pow(1 - t, 3) }
    static func inOut(_ t: Float) -> Float { t <= 0 ? 0 : t >= 1 ? 1 : t * t * (3 - 2 * t) }
    static func seg(_ t: Float, _ a: Float, _ b: Float) -> Float { max(0, min(1, (t - a) / (b - a))) }
    static func back(_ x0: Float) -> Float {
        let x = max(0, min(1, x0)), c: Float = 1.9
        return 1 + (c + 1) * pow(x - 1, 3) + c * pow(x - 1, 2)
    }
    static func spring(_ u: Float, _ amp: Float, _ k: Float = 7, _ w: Float = 20) -> Float {
        u < 0 ? 0 : amp * exp(-k * u) * cos(w * u)
    }
}

/// A camera node like three.js PerspectiveCamera(fov, aspect, .1, 50).
func makeCamera(fov: CGFloat) -> SCNNode {
    let cam = SCNCamera()
    cam.projectionDirection = .vertical
    cam.fieldOfView = fov
    cam.zNear = 0.1
    cam.zFar = 50
    let n = SCNNode()
    n.camera = cam
    return n
}
