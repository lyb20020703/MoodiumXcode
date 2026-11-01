import SceneKit
import UIKit

/// The four gifts from the visionOS reward tables (CandyWorldRewardTable / NatureWorldRewardTable).
/// In the headset they grow in your room at 20 / 50 / 80 / 100 % energy; on the phone they grow
/// on little glowing spots either side of the pillow and stay for the visit.
struct Gift {
    let zh: String
    let en: String
    /// Models (with an optional candy colour) and the height on screen in stage units.
    let parts: [(name: String, tint: UIColor?)]
    let height: Float
    /// Tree and house exports are Z-up; the small burst props are not.
    let upright: Bool

    func name(_ l: Language) -> String { l == .zh ? zh : en }

    static func all(for world: MoodWorld) -> [Gift] {
        switch world {
        case .candy:
            return [
                Gift(zh: "糖果三重奏", en: "Candy Trio",
                     parts: [("Macaron", UIColor(red: 1, green: 0.7, blue: 0.82, alpha: 1)),
                             ("star", UIColor(red: 1, green: 0.84, blue: 0.42, alpha: 1)),
                             ("heart", UIColor(red: 1, green: 0.48, blue: 0.66, alpha: 1))], height: 0.75, upright: false),
                Gift(zh: "曲奇和巧克力", en: "Cookie and Chocolate",
                     parts: [("cookie", UIColor(red: 0.86, green: 0.6, blue: 0.32, alpha: 1)),
                             ("chocolate", UIColor(red: 0.42, green: 0.24, blue: 0.15, alpha: 1))], height: 0.95, upright: false),
                Gift(zh: "小糖果屋", en: "Little Candy House", parts: [("CandyLittleHouse", nil)], height: 1.55, upright: true),
                Gift(zh: "糖果屋", en: "Candy House", parts: [("CandyHouse", nil)], height: 2.1, upright: true),
            ]
        case .nature:
            return [
                Gift(zh: "小花和蘑菇", en: "Flowers and Mushrooms",
                     parts: [("flower", nil), ("mushroom", nil), ("leaf_lofi", nil)], height: 0.75, upright: false),
                Gift(zh: "杜松灌木", en: "Juniper Shrub", parts: [("Juniper", nil)], height: 1.4, upright: true),
                Gift(zh: "小橡树", en: "Little Oak", parts: [("Oak", nil)], height: 1.9, upright: true),
                Gift(zh: "松树", en: "Pine Tree", parts: [("Pine", nil)], height: 2.4, upright: true),
            ]
        }
    }

    static let stages: [Double] = [0.2, 0.5, 0.8, 1.0]
}

final class GiftGarden {
    let root = SCNNode()
    let gifts: [Gift]
    private let accent: UIColor
    private var models: [SCNNode?] = [nil, nil, nil, nil]
    private var spots: [SCNNode] = []
    private var slots: [SCNNode] = []
    private(set) var grown: Set<Int> = []
    private let depth: Float = -0.6

    /// Screen anchors: x as a fraction of half-width, base y as a fraction of half-height.
    /// Small gifts sit nearer the pillow, the big ones further out.
    private let anchors: [SIMD2<Float>] = [[-0.62, -0.5], [0.62, -0.5], [-0.84, -0.4], [0.84, -0.4]]

    init(world: MoodWorld) {
        gifts = Gift.all(for: world)
        accent = UIColor(world.accent)
        for i in 0..<4 {
            let slot = SCNNode()
            slot.isHidden = true
            root.addChildNode(slot)
            slots.append(slot)
            let spot = SCNNode(geometry: SCNPlane(width: 1, height: 0.3))
            let m = SCNMaterial()
            m.diffuse.contents = UIImage(named: "glow_radial")
            m.multiply.contents = accent
            m.lightingModel = .constant
            m.blendMode = .add
            m.writesToDepthBuffer = false
            spot.geometry?.materials = [m]
            spot.opacity = 0
            spot.renderingOrder = -5
            root.addChildNode(spot)
            spots.append(spot)
            _ = i
        }
    }

    /// Load the models off the main thread.
    func load() {
        for (i, gift) in gifts.enumerated() {
            let group = SCNNode()
            var parts: [SCNNode] = []
            for (name, tint) in gift.parts {
                let extent = gift.parts.count > 1 ? gift.height * 0.62 : gift.height
                guard let loaded = ModelLoader.load(name, extent: extent, pitch: gift.upright ? -.pi / 2 : 0, bottomPivot: true) else { continue }
                if let tint { ModelLoader.paint(loaded.node, tint, roughness: 0.4) }
                if gift.upright { GiftGarden.fixFoliage(loaded.node) }
                parts.append(loaded.node)
            }
            // spread a little cluster side by side, the middle one a touch taller
            for (k, node) in parts.enumerated() {
                let n = Float(parts.count)
                node.position.x = (Float(k) - (n - 1) / 2) * gift.height * 0.5
                node.position.z = k % 2 == 0 ? 0 : -0.15
                if parts.count > 1 && k == parts.count / 2 { node.scale = SCNVector3(1.15, 1.15, 1.15) }
                node.eulerAngles.y = Float.random(in: -0.5...0.5)
                group.addChildNode(node)
            }
            models[i] = group
        }
    }

    /// Leaves are alpha-cut cards: draw both sides and cut them out on alpha instead of
    /// blending (blending made the trees look like ghosts).
    private static func fixFoliage(_ node: SCNNode) {
        node.enumerateHierarchy { child, _ in
            child.geometry?.materials.forEach { m in
                m.isDoubleSided = true
                m.lightingModel = .physicallyBased
                m.roughness.contents = 0.85
                guard m.transparent.contents is URL || m.transparent.contents is UIImage || m.transparent.contents is String else { return }
                // the leaf texture's alpha is also in the diffuse map: cut on it, draw opaque
                m.transparent.contents = nil
                m.transparency = 1
                m.writesToDepthBuffer = true
                m.shaderModifiers = [.surface: "if (_surface.diffuse.a < 0.5) { discard_fragment(); }"]
            }
        }
    }

    /// Place the slots for the current stage size.
    func layout(halfW: Float, halfH: Float, cameraDistance: Float) {
        let k = (cameraDistance - depth) / cameraDistance
        for i in 0..<4 {
            let a = anchors[i]
            let p = SCNVector3(a.x * halfW * k, a.y * halfH * k, depth)
            slots[i].position = p
            spots[i].position = SCNVector3(p.x, p.y + 0.02, depth - 0.05)
            let w = CGFloat(gifts[i].height * 1.25 + 0.4)
            (spots[i].geometry as? SCNPlane)?.width = w
            (spots[i].geometry as? SCNPlane)?.height = w * 0.32
        }
    }

    /// Grow gift `i` (0…3) in with a springy spin. Returns false if it was already there.
    @discardableResult
    func grow(_ i: Int) -> Bool {
        guard i >= 0, i < 4, !grown.contains(i), let model = models[i] else { return false }
        grown.insert(i)
        let slot = slots[i]
        slot.childNodes.forEach { $0.removeFromParentNode() }
        let holder = SCNNode()
        holder.addChildNode(model.clone())
        slot.addChildNode(holder)
        slot.isHidden = false
        holder.scale = SCNVector3(0.01, 0.01, 0.01)
        holder.eulerAngles.y = -.pi
        let up = SCNAction.scale(to: 1.15, duration: 0.45); up.timingMode = .easeOut
        let settle = SCNAction.scale(to: 1, duration: 0.25); settle.timingMode = .easeInEaseOut
        let spin = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.7, usesShortestUnitArc: false); spin.timingMode = .easeOut
        holder.runAction(.group([.sequence([up, settle]), spin])) {
            // gentle sway while it stays
            let sway = SCNAction.sequence([.rotateTo(x: 0, y: 0.32, z: 0, duration: 2.6), .rotateTo(x: 0, y: -0.32, z: 0, duration: 2.6)])
            sway.timingMode = .easeInEaseOut
            holder.runAction(.repeatForever(sway))
        }
        spots[i].runAction(.fadeOpacity(to: 0.85, duration: 0.5))
        return true
    }

    /// Everything goes away (again / new visit).
    func clear() {
        grown.removeAll()
        for (slot, spot) in zip(slots, spots) {
            slot.runAction(.sequence([.scale(to: 0.01, duration: 0.25), .hide(), .run { $0.childNodes.forEach { $0.removeFromParentNode() }; $0.scale = SCNVector3(1, 1, 1) }]))
            spot.runAction(.fadeOpacity(to: 0, duration: 0.25))
        }
    }

    /// World-space middle of gift `i`, for 2D sparkles.
    func center(_ i: Int) -> SCNVector3 {
        let p = slots[i].position
        return SCNVector3(p.x, p.y + gifts[i].height * 0.45, p.z)
    }
}
