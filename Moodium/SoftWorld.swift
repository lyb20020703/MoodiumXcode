import SwiftUI
import SceneKit

// Normalizes imported geometry without changing authored mesh/material data.
private func asset(_ name: String, extent: Float) -> SCNNode? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "usdz"),
          let source = try? SCNScene(url: url, options: nil) else { return nil }
    let content = SCNNode()
    for child in source.rootNode.childNodes { content.addChildNode(child) }
    let (lo, hi) = content.boundingBox
    let length = max(hi.x-lo.x, max(hi.y-lo.y, hi.z-lo.z))
    guard length > 0 else { return nil }
    let factor = extent / length
    content.scale = SCNVector3(factor, factor, factor)
    content.position = SCNVector3(-(lo.x+hi.x)*factor/2, -(lo.y+hi.y)*factor/2, -(lo.z+hi.z)*factor/2)
    let wrapper = SCNNode(); wrapper.addChildNode(content)
    return wrapper
}

final class SoftWorld: ObservableObject {
    let scene = SCNScene()
    let camera = SCNNode()
    private var soft = SCNNode()
    private let particles = SCNNode()
    private let walls = SCNNode()
    private var pool: [SCNNode] = []
    private var halfWidth: Float = 6
    private var halfHeight: Float = 3.5
    init() {
        camera.camera = SCNCamera(); camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 7
        camera.position = SCNVector3(0, 0, 15)
        scene.rootNode.addChildNode(camera)
        scene.rootNode.addChildNode(particles); scene.rootNode.addChildNode(walls)
        scene.physicsWorld.gravity = SCNVector3(0, -2.2, 0)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 650; scene.rootNode.addChildNode(ambient)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .omni
        key.light?.intensity = 1100; key.position = SCNVector3(-4, 6, 8)
        scene.rootNode.addChildNode(key)
    }
    func configure(nature: Bool) {
        clear(); soft.removeFromParentNode()
        soft = asset(nature ? "NatureSoft" : "CandySoft", extent: 5.0) ?? SCNNode()
        scene.rootNode.addChildNode(soft)
        pool = (nature ? ["leaf_lofi", "flower", "mushroom"] : ["chocolate", "cookie", "heart", "star", "Macaron"])
            .compactMap { asset($0, extent: 0.36) }
    }
    func clear() { particles.childNodes.forEach { $0.removeFromParentNode() } }
    func resize(_ size: CGSize) {
        guard size.height > 0 else { return }
        halfHeight = 3.5; halfWidth = halfHeight * Float(size.width / size.height)
        walls.childNodes.forEach { $0.removeFromParentNode() }
        for (x,y,w,h) in [(halfWidth+0.15,Float(0),Float(0.3),halfHeight*2+1),(-halfWidth-0.15,0,0.3,halfHeight*2+1),(0,halfHeight+0.15,halfWidth*2+1,0.3),(0,-halfHeight-0.15,halfWidth*2+1,0.3)] {
            let node = SCNNode()
            node.position = SCNVector3(x,y,0)
            node.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: SCNBox(width: CGFloat(w), height: CGFloat(h), length: 12, chamferRadius: 0)))
            node.physicsBody?.restitution = 0.85; walls.addChildNode(node)
        }
    }
    func burst() {
        soft.removeAllActions()
        soft.runAction(.sequence([.scale(to: 0.84, duration: 0.10), .scale(to: 1.06, duration: 0.12), .scale(to: 1, duration: 0.2)]))
        guard !pool.isEmpty else { return }
        for _ in 0..<12 {
            if particles.childNodes.count >= 96 { particles.childNodes.first?.removeFromParentNode() }
            let node = pool.randomElement()!.clone()
            node.position = SCNVector3(Float.random(in: -0.3...0.3), 0, 2.8)
            node.eulerAngles = SCNVector3(Float.random(in: 0...6),Float.random(in: 0...6),0)
            let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: SCNSphere(radius: 0.16)))
            body.mass = 0.1; body.restitution = 0.85; body.friction = 0.1; body.damping = 0.08
            body.velocityFactor = SCNVector3(1,1,0)
            body.velocity = SCNVector3(Float.random(in: -5...5),Float.random(in: 2...6),0)
            body.angularVelocity = SCNVector4(0,1,1,Float.random(in: -5...5))
            node.physicsBody = body; particles.addChildNode(node)
            node.runAction(.sequence([.wait(duration: 4), .fadeOut(duration: 1), .removeFromParentNode()]))
        }
    }
}

struct SoftSceneView: UIViewRepresentable {
    let world: SoftWorld
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(); view.backgroundColor = .clear
        view.scene = world.scene; view.pointOfView = world.camera
        view.isPlaying = true; view.antialiasingMode = .multisampling4X
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {}
}
