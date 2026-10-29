import SceneKit
import UIKit

/// Loads a USDZ exported from the Unity FBX and normalises it without touching authored
/// meshes or materials: centred on the origin and scaled so its largest side equals `extent`.
enum ModelLoader {
    struct Loaded {
        let node: SCNNode
        /// Size after scaling, in the returned node's space.
        let size: SIMD3<Float>
    }

    static func load(_ name: String, extent: Float, pitch: Float = 0, bottomPivot: Bool = false) -> Loaded? {
        guard let url = Res.url(name, "usdz"),
              let source = try? SCNScene(url: url, options: [.checkConsistency: false]) else { return nil }
        let content = SCNNode()
        for child in source.rootNode.childNodes { content.addChildNode(child) }

        let rotated = SCNNode()
        rotated.eulerAngles.x = pitch
        rotated.addChildNode(content)
        let mid = SCNNode()
        mid.addChildNode(rotated)

        let (lo, hi) = mid.boundingBox
        let size = SIMD3<Float>(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
        let longest = max(size.x, max(size.y, size.z))
        guard longest > 0 else { return nil }
        rotated.position = SCNVector3(-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -(lo.z + hi.z) / 2)

        let factor = extent / longest
        mid.scale = SCNVector3(factor, factor, factor)
        let scaled = size * factor
        if bottomPivot { mid.position.y = scaled.y / 2 }

        let outer = SCNNode()
        outer.name = name
        outer.addChildNode(mid)
        return Loaded(node: outer, size: scaled)
    }

    /// The Unity candy props rely on material overrides that the FBX → USDZ export dropped,
    /// so they arrive white. Re-apply soft candy colours (each call makes its own material copy).
    static func paint(_ node: SCNNode, _ color: UIColor, roughness: CGFloat = 0.42, clearCoat: CGFloat = 0.5) {
        node.enumerateHierarchy { child, _ in
            guard let geometry = child.geometry else { return }
            let copy = geometry.copy() as! SCNGeometry
            copy.materials = geometry.materials.map { original in
                let m = original.copy() as! SCNMaterial
                m.lightingModel = .physicallyBased
                m.diffuse.contents = color
                m.metalness.contents = 0.0
                m.roughness.contents = roughness
                m.clearCoat.contents = clearCoat
                m.clearCoatRoughness.contents = 0.25
                return m
            }
            child.geometry = copy
        }
    }
}
