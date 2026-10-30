import SceneKit
import UIKit
import simd

/// The 3D half of the squeeze scene.
///
/// - The world's 360° panorama is the background and also lights the models.
/// - CandySoft / NatureSoft sits in the middle as a jelly pillow driven by a damped spring:
///   each squeeze squashes it, it rebounds past rest and wobbles twice, leaning toward the
///   side that was pressed.
/// - Each squeeze throws the world's props (the Unity burst prefabs) out of the pillow. They
///   live on a plane facing the camera, fall with the phone's real gravity, land on the
///   pillow, and bounce off invisible walls exactly at the screen edges.
final class SoftStage: NSObject, SCNSceneRendererDelegate, SCNPhysicsContactDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let world: MoodWorld
    weak var view: SCNView?

    /// Called on the main thread when a prop hits a screen edge (UIKit point, strength 0…1).
    var onEdgeHit: ((CGPoint, Double) -> Void)?

    private enum Category {
        static let prop = 1 << 1
        static let wall = 1 << 2
        static let jelly = 1 << 3
    }

    private let jellyRoot = SCNNode()    // placement + entrance/exit actions
    private let jellySpring = SCNNode()  // per-frame squash & lean
    private let jellyTilt = SCNNode()
    private(set) var rescue: MoodiRescueRig?
    var usesMeshMoodi: Bool { rescue != nil }
    var onSplash: (() -> Void)?
    var onPop: (() -> Void)?
    var onFree: (() -> Void)?
    private(set) var modelsReady = false
    var onReady: (() -> Void)?
    private var layoutSize = CGSize.zero
    func withRescue(_ action: (MoodiRescueRig) -> Void) { lock.lock(); defer { lock.unlock() }; if let rescue { action(rescue) } }
    func rescueFallIn() {
        withRescue { rig in rig.fallIn(from: rig.node.simdConvertPosition(SIMD3(halfW * 0.95, halfH * 1.05, 0), from: scene.rootNode)) }
    }
    func mouthScreenPoint() -> CGPoint? {
        guard let rescue, let view else { return nil }
        let p = view.projectPoint(rescue.node.convertPosition(SCNVector3Zero, to: nil))
        return CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
    }
    private let jellyFit = SCNNode()     // scales the unit-width model to the screen
    private let jellyBody = SCNNode()
    private let props = SCNNode()
    private let walls = SCNNode()
    private var templates: [SCNNode] = []

    private let lock = NSLock()
    private var squash: Float = 0, squashVel: Float = 0
    private var lean: Float = 0, leanVel: Float = 0
    private var hold: Float = 0
    private var lastTime: TimeInterval = 0
    private var parallax = SIMD2<Float>(0, 0)
    private var parallaxTarget = SIMD2<Float>(0, 0)

    // Layout in world units on the prop plane (z = 0).
    private(set) var halfW: Float = 4
    private(set) var halfH: Float = 2
    private var jellyWidth: Float = 2
    private var jellyHeight: Float = 1.3
    private var jellyBottomY: Float = -1
    /// Top of the pillow collider on the prop plane.
    private var jellyTopY: Float = 0
    private let jellyZ: Float = -0.7
    private let jellyAspect: Float = 0.642
    private let cameraDistance: Float = 10
    private let fov: Float = 40

    private var lastContact: TimeInterval = 0

    init(world: MoodWorld) {
        self.world = world
        super.init()

        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(fov)
        camera.zNear = 0.1
        camera.zFar = 100
        camera.wantsHDR = true
        camera.bloomIntensity = 0.35
        camera.bloomThreshold = 0.85
        camera.wantsExposureAdaptation = false
        camera.vignettingIntensity = 0.35
        camera.vignettingPower = 0.6
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, cameraDistance)
        scene.rootNode.addChildNode(cameraNode)

        let pano = Res.image(world.panorama)
        scene.background.contents = pano
        scene.lightingEnvironment.contents = pano
        scene.lightingEnvironment.intensity = 1.25

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 650
        key.light?.color = world == .candy ? UIColor(red: 1, green: 0.93, blue: 0.96, alpha: 1) : UIColor(red: 0.95, green: 1, blue: 0.9, alpha: 1)
        key.eulerAngles = SCNVector3(-0.6, -0.4, 0)
        scene.rootNode.addChildNode(key)

        scene.physicsWorld.gravity = SCNVector3(0, -7, 0)
        scene.physicsWorld.contactDelegate = self
        scene.physicsWorld.timeStep = 1.0 / 90

        jellyFit.addChildNode(SCNNode()) // placeholder until the model loads
        jellyTilt.addChildNode(jellyFit)
        jellySpring.addChildNode(jellyTilt)
        jellyRoot.addChildNode(jellySpring)
        scene.rootNode.addChildNode(jellyRoot)
        scene.rootNode.addChildNode(jellyBody)
        scene.rootNode.addChildNode(props)
        scene.rootNode.addChildNode(walls)

        loadModels()
    }

    // MARK: - Loading

    private func loadModels() {
        let world = self.world
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var rig: MoodiRescueRig?
            if !UserDefaults.standard.bool(forKey: "MoodiSprite"),
               let soft = Res.url(world.softModel + "_Mouth", "usdz"), let moodi = Res.url("Moodi", "usdz"),
               let tracks = Res.url(world.softModel + "_MoodiTracks", "json") {
                rig = MoodiRescueRig(softURL: soft, moodiURL: moodi, tracksURL: tracks)
            }
            let loadedRig = rig
            let jelly = ModelLoader.load(world.softModel, extent: 1, bottomPivot: true)
            let templates = SoftStage.makeTemplates(for: world)
            DispatchQueue.main.async {
                guard let self else { return }
                self.templates = templates
                if let rig = loadedRig {
                    self.lock.lock()
                    self.rescue = rig
                    self.jellyFit.childNodes.forEach { $0.removeFromParentNode() }
                    self.jellyFit.addChildNode(rig.node)
                    rig.onSplash = { [weak self] in DispatchQueue.main.async { self?.onSplash?() } }
                    rig.onPop = { [weak self] in DispatchQueue.main.async { self?.onPop?() } }
                    rig.onFree = { [weak self] in DispatchQueue.main.async { self?.onFree?() } }
                    self.lock.unlock()
                } else if let jelly {
                    self.jellyFit.childNodes.forEach { $0.removeFromParentNode() }
                    self.jellyFit.addChildNode(jelly.node)
                }
                self.resize(self.layoutSize)
                print("[Moodi Emergence] display = \(self.usesMeshMoodi ? "mesh" : "sprite")")
                self.modelsReady = true
                self.onReady?()
            }
        }
    }

    /// The Unity burst prefabs: Candy = chocolate, cookie, heart, star, macaron;
    /// Nature = leaf, flower, mushroom. Candy props get their colours back.
    private static func makeTemplates(for world: MoodWorld) -> [SCNNode] {
        let size: Float = 0.62
        func load(_ name: String) -> SCNNode? { ModelLoader.load(name, extent: size)?.node }
        var out: [SCNNode] = []
        switch world {
        case .candy:
            let tints: [(String, UIColor, CGFloat)] = [
                ("chocolate", UIColor(red: 0.42, green: 0.24, blue: 0.15, alpha: 1), 0.35),
                ("cookie", UIColor(red: 0.86, green: 0.6, blue: 0.32, alpha: 1), 0.6),
                ("heart", UIColor(red: 1.0, green: 0.48, blue: 0.66, alpha: 1), 0.3),
                ("star", UIColor(red: 1.0, green: 0.84, blue: 0.42, alpha: 1), 0.32),
                ("star", UIColor(red: 0.78, green: 0.68, blue: 1.0, alpha: 1), 0.32),
                ("Macaron", UIColor(red: 1.0, green: 0.7, blue: 0.82, alpha: 1), 0.55),
                ("Macaron", UIColor(red: 0.66, green: 0.9, blue: 0.78, alpha: 1), 0.55),
                ("Macaron", UIColor(red: 0.8, green: 0.74, blue: 1.0, alpha: 1), 0.55),
                ("Macaron", UIColor(red: 1.0, green: 0.92, blue: 0.62, alpha: 1), 0.55),
            ]
            var cache: [String: SCNNode] = [:]
            for (name, color, roughness) in tints {
                guard let base = cache[name] ?? load(name) else { continue }
                cache[name] = base
                let node = base.clone()
                ModelLoader.paint(node, color, roughness: roughness)
                out.append(node)
            }
        case .nature:
            for name in ["leaf_lofi", "flower", "mushroom", "flower", "leaf_lofi"] {
                if let node = load(name) { out.append(node) }
            }
        }
        return out
    }

    // MARK: - Layout

    /// Fits the prop plane, walls and pillow to the view size.
    func resize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        layoutSize = size
        halfH = cameraDistance * tan(fov * .pi / 360)
        halfW = halfH * Float(size.width / size.height)

        // The pillow takes ~46 % of the screen height, sitting a little below centre so the
        // energy ring can float above it (as in the visionOS layout).
        let depthScale = (cameraDistance - jellyZ) / cameraDistance
        jellyHeight = min(halfH * 0.92, halfW * 0.62 * jellyAspect) * depthScale
        jellyWidth = jellyHeight / jellyAspect
        jellyBottomY = -halfH * 0.66 * depthScale
        jellyRoot.position = SCNVector3(0, jellyBottomY, jellyZ)
        jellyFit.scale = SCNVector3(jellyWidth, jellyWidth, jellyWidth)

        if let rescue {
            let b = rescue.softBounds
            let k = min(2 * halfW * 0.52 * depthScale / (b.max.x - b.min.x), halfH * 1.8 / (b.max.y - b.min.y + 2.3))
            jellyFit.simdScale = SIMD3(repeating: k)
            let c = (b.min + b.max) / 2
            jellyFit.simdPosition = -SIMD3(c.x, b.min.y, c.z) * k
            jellyTilt.simdOrientation = simd_quatf(angle: 38 * .pi / 180, axis: SIMD3(1, 0, 0))
            jellyRoot.simdPosition = SIMD3(0, -0.5 * halfH * depthScale, jellyZ)
            if let rect = jellyScreenRect(), let view, view.bounds.height > 0 {
                let unit = 2 * halfH / Float(view.bounds.height)
                jellyWidth = Float(rect.width) * unit * depthScale
                jellyHeight = Float(rect.height) * unit * depthScale
                jellyBottomY = (halfH - Float(rect.maxY) * unit) * depthScale
            }
        }
        // Static collider for the pillow on the prop plane.
        let planeW = jellyWidth / depthScale * 0.86
        let planeH = jellyHeight / depthScale * 0.8
        jellyBody.physicsBody = nil
        jellyBody.position = SCNVector3(0, jellyBottomY / depthScale + planeH / 2, 0)
        let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: SCNBox(width: CGFloat(planeW), height: CGFloat(planeH), length: 3, chamferRadius: CGFloat(planeH * 0.35))))
        body.restitution = 0.9
        body.friction = 0.4
        body.categoryBitMask = Category.jelly
        jellyBody.physicsBody = body
        jellyTopY = jellyBody.position.y + planeH / 2

        walls.childNodes.forEach { $0.removeFromParentNode() }
        let t: Float = 1
        let specs: [(Float, Float, Float, Float)] = [
            (halfW + t / 2, 0, t, halfH * 2 + 2 * t),
            (-halfW - t / 2, 0, t, halfH * 2 + 2 * t),
            (0, halfH + t / 2, halfW * 2 + 2 * t, t),
            (0, -halfH - t / 2, halfW * 2 + 2 * t, t),
        ]
        for (x, y, w, h) in specs {
            let wall = SCNNode()
            wall.position = SCNVector3(x, y, 0)
            let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: SCNBox(width: CGFloat(w), height: CGFloat(h), length: 4, chamferRadius: 0)))
            body.restitution = 0.8
            body.friction = 0.2
            body.categoryBitMask = Category.wall
            wall.physicsBody = body
            walls.addChildNode(wall)
        }
    }

    /// Pillow geometry in UIKit points, for placing 2D effects and Moodi.
    func jellyScreenRect() -> CGRect? {
        guard let view else { return nil }
        if let rescue {
            let b = rescue.softBounds
            let points = [b.min.x, b.max.x].flatMap { x in [b.min.y,b.max.y].flatMap { y in [b.min.z,b.max.z].map { z in view.projectPoint(rescue.node.convertPosition(SCNVector3(x,y,z), to: nil)) } } }
            let xs = points.map { CGFloat($0.x) }, ys = points.map { CGFloat($0.y) }
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
        let bl = view.projectPoint(SCNVector3(-jellyWidth / 2, jellyBottomY, jellyZ))
        let tr = view.projectPoint(SCNVector3(jellyWidth / 2, jellyBottomY + jellyHeight, jellyZ))
        return CGRect(x: CGFloat(bl.x), y: CGFloat(tr.y), width: CGFloat(tr.x - bl.x), height: CGFloat(bl.y - tr.y))
    }

    // MARK: - Squeeze input (main thread)

    /// A squeeze: squash the pillow, lean toward the pressed side, bounce resting props.
    func kick(_ intensity: Double, side: Double) {
        let i = Float(intensity)
        lock.lock()
        squashVel += 5.5 + 5 * i
        leanVel += Float(side) * (2.5 + 3 * i)
        lock.unlock()

        // Trampoline: props resting on the pillow get tossed up.
        let top = jellyTopY
        for prop in props.childNodes {
            guard let body = prop.physicsBody else { continue }
            let p = prop.presentation.position
            if abs(p.x) < jellyWidth * 0.55, p.y < top + 0.7, p.y > top - 0.3 {
                body.applyForce(SCNVector3(-Float(side) * 0.15 + Float.random(in: -0.1...0.1), 0.35 + 0.35 * i, 0), asImpulse: true)
            }
        }
    }

    /// Touch mode: how far the pillow is held down (0…1).
    func setHold(_ amount: Double) {
        lock.lock(); hold = Float(amount) * 0.32; lock.unlock()
    }

    /// Throws props out of the pillow, away from the pressed side (CandyBurstController: 2–4,
    /// one every 45 ms; the phone gets a couple more since they stay on screen longer).
    func burst(_ intensity: Double, side: Double) {
        guard !templates.isEmpty else { return }
        let count = 2 + Int((intensity * 4).rounded())
        for n in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.045 * Double(n)) { [weak self] in
                guard let self else { return }
                let mouth = self.rescue?.node.convertPosition(SCNVector3Zero, to: nil)
                let centerX = (mouth?.x ?? 0) * self.cameraDistance / (self.cameraDistance - (mouth?.z ?? 0))
                let x = centerX + Float.random(in: -0.2...0.2) * self.jellyWidth
                let y = self.jellyTopY + 0.35
                let vx = -Float(side) * Float.random(in: 1.2...3.2) + Float.random(in: -1.8...1.8)
                let vy = Float.random(in: 5.5...8.0) * Float(0.75 + 0.35 * intensity)
                self.spawnProp(at: SIMD2(x, y), velocity: SIMD2(vx, vy))
            }
        }
    }

    /// Celebration: props rain from the top edge for a while.
    func rain(duration: TimeInterval, every: TimeInterval = 0.07) {
        let steps = Int(duration / every)
        for n in 0..<steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(n) * every) { [weak self] in
                guard let self else { return }
                let x = Float.random(in: -0.92...0.92) * self.halfW
                self.spawnProp(at: SIMD2(x, self.halfH - 0.4), velocity: SIMD2(Float.random(in: -1...1), Float.random(in: -2...0)))
            }
        }
    }

    /// Shake / slosh: shove every prop.
    func scatter(_ strength: Float = 1) {
        for prop in props.childNodes {
            prop.physicsBody?.applyForce(SCNVector3(Float.random(in: -0.6...0.6) * strength, Float.random(in: 0.2...0.7) * strength, 0), asImpulse: true)
        }
    }

    private func spawnProp(at p: SIMD2<Float>, velocity v: SIMD2<Float>) {
        guard let template = templates.randomElement() else { return }
        if props.childNodes.count >= 44 { props.childNodes.first?.removeFromParentNode() }
        let node = template.clone()
        node.position = SCNVector3(p.x, p.y, 0)
        node.eulerAngles = SCNVector3(Float.random(in: 0...6.28), Float.random(in: 0...6.28), Float.random(in: 0...6.28))
        let s = Float.random(in: 0.8...1.15)
        node.scale = SCNVector3(0.2, 0.2, 0.2)
        node.runAction(.scale(to: CGFloat(s), duration: 0.18))

        let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: SCNSphere(radius: CGFloat(0.25 * s))))
        body.mass = 0.1
        body.restitution = 0.72
        body.friction = 0.35
        body.rollingFriction = 0.02
        body.damping = 0.04
        body.angularDamping = 0.15
        body.velocityFactor = SCNVector3(1, 1, 0)
        body.categoryBitMask = Category.prop
        body.collisionBitMask = Category.prop | Category.wall | Category.jelly
        body.contactTestBitMask = Category.wall
        body.velocity = SCNVector3(v.x, v.y, 0)
        body.angularVelocity = SCNVector4(Float.random(in: -1...1), Float.random(in: -1...1), 1, Float.random(in: -6...6))
        node.physicsBody = body
        props.addChildNode(node)

        node.runAction(.sequence([.wait(duration: 6.5 + Double.random(in: 0...1.5)),
                                  .group([.fadeOut(duration: 0.7), .scale(to: 0.05, duration: 0.7)]),
                                  .removeFromParentNode()]))
    }

    // MARK: - Pillow life cycle

    /// Completion: bulge, then pop out of existence with a big burst.
    func popJelly() {
        let bulge = SCNAction.scale(to: 1.14, duration: 0.28)
        bulge.timingMode = .easeOut
        let vanish = SCNAction.scale(to: 0.01, duration: 0.16)
        vanish.timingMode = .easeIn
        jellyRoot.runAction(.sequence([bulge, .wait(duration: 0.1), vanish, .hide()]))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.jellyBody.physicsBody?.categoryBitMask = 0
            self?.burst(1, side: 0)
            self?.burst(1, side: 0)
        }
    }

    /// Bring the pillow back with a springy grow-in.
    func regrowJelly() {
        jellyRoot.removeAllActions()
        jellyRoot.scale = SCNVector3(0.01, 0.01, 0.01)
        jellyRoot.isHidden = false
        let grow = SCNAction.scale(to: 1.08, duration: 0.35)
        grow.timingMode = .easeOut
        let settle = SCNAction.scale(to: 1, duration: 0.25)
        settle.timingMode = .easeInEaseOut
        jellyRoot.runAction(.sequence([grow, settle]))
        jellyBody.physicsBody?.categoryBitMask = Category.jelly
        lock.lock(); squash = 0; squashVel = 0; lean = 0; leanVel = 0; lock.unlock()
    }

    func clearProps() {
        for prop in props.childNodes {
            prop.runAction(.sequence([.fadeOut(duration: 0.3), .removeFromParentNode()]))
        }
    }

    // MARK: - Device motion (main thread)

    /// Gravity follows the phone: tilt the base and the props roll that way.
    func setGravity(_ g: SIMD2<Double>) {
        scene.physicsWorld.gravity = SCNVector3(Float(g.x) * 9, Float(g.y) * 9, 0)
    }

    /// A slight look-around in the panorama as the phone rocks.
    func setParallax(_ tilt: SIMD2<Double>) {
        lock.lock()
        parallaxTarget = SIMD2(Float(max(-0.5, min(0.5, tilt.x))), Float(max(-0.5, min(0.5, tilt.y))))
        lock.unlock()
    }

    // MARK: - Per frame (render thread)

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = Float(min(1.0 / 20, lastTime == 0 ? 1.0 / 60 : time - lastTime))
        lastTime = time

        lock.lock()
        // Underdamped springs: overshoot the rest pose and wobble about twice, like jelly.
        let breathing = 0.012 * Float(sin(time * 1.7))
        let target = hold + breathing
        squashVel += (-150 * (squash - target) - 7.5 * squashVel) * dt
        squash += squashVel * dt
        squash = max(-0.35, min(0.55, squash))
        leanVel += (-95 * lean - 6 * leanVel) * dt
        lean += leanVel * dt
        parallax += (parallaxTarget - parallax) * min(1, dt * 4)
        rescue?.update(dt: dt)
        let s = squash * (rescue == nil ? 1 : 0.6), l = lean, px = parallax
        lock.unlock()

        jellySpring.scale = SCNVector3(1 + 0.42 * s, 1 - 0.5 * s, 1 + 0.3 * s)
        jellySpring.eulerAngles = SCNVector3(0.05 * s, 0, -0.14 * l)
        jellySpring.position.x = 0.12 * l * jellyWidth

        let yaw = px.x * 0.12
        let pitch = -0.06 + px.y * 0.05
        scene.background.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeRotation(yaw, 0, 1, 0), SCNMatrix4MakeRotation(pitch, 1, 0, 0))
    }

    // MARK: - Contacts (render thread)

    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        let a = contact.nodeA.physicsBody?.categoryBitMask ?? 0
        let b = contact.nodeB.physicsBody?.categoryBitMask ?? 0
        guard (a | b) & Category.wall != 0, (a | b) & Category.prop != 0 else { return }
        let impulse = Double(contact.collisionImpulse)
        guard impulse > 0.12 else { return }
        let now = CACurrentMediaTime()
        guard now - lastContact > 0.03 else { return }
        lastContact = now

        // Pin the hit to the exact screen edge it touched.
        var p = contact.contactPoint
        p.x = max(-halfW, min(halfW, p.x))
        p.y = max(-halfH, min(halfH, p.y))
        let strength = min(1, impulse / 1.4)
        DispatchQueue.main.async { [weak self] in
            guard let self, let view = self.view else { return }
            let s = view.projectPoint(SCNVector3(p.x, p.y, 0))
            self.onEdgeHit?(CGPoint(x: CGFloat(s.x), y: CGFloat(s.y)), strength)
        }
    }
}
