import SpriteKit
import UIKit

/// The 2D half of the squeeze scene, drawn over the 3D stage:
/// - squeeze bursts (Epic Toon FX sparkle / star / ring textures used by the visionOS VFX),
/// - bouncy sugar beads / seeds that ricochet off the screen edges,
/// - a glow that flares along the edge wherever something hits it,
/// - ambient sugar frost (Candy) or leaves and fireflies (Nature) that grow with energy,
///   following CandyFrostParticleController's curve,
/// - Moodi, who falls into the pillow and is squeezed back out.
final class SparkleScene: SKScene, SKPhysicsContactDelegate {
    let world: MoodWorld
    var onMoteEdgeHit: ((CGPoint, Double) -> Void)?

    private enum Category {
        static let mote: UInt32 = 1 << 0
        static let edge: UInt32 = 1 << 1
    }

    private let ambientLayer = SKNode()
    private let moteLayer = SKNode()
    private let fxLayer = SKNode()
    private let moodi = SKSpriteNode(imageNamed: "moodi_happy")
    private let moodiShadow = SKSpriteNode(imageNamed: "fx_glow")
    private var ambient: [(SKEmitterNode, Double)] = []   // emitter + max birth rate
    private var fireflies: SKEmitterNode?
    private var energy: Double = 0
    private var lastSplash: TimeInterval = 0
    private var gravity = CGVector(dx: 0, dy: -1)

    /// Pillow rect in SpriteKit coordinates (origin bottom-left).
    var spriteMoodi = true
    private var mouthPoint: CGPoint?
    func setMouthPoint(_ point: CGPoint?) { mouthPoint = point.map { toScene($0) } }
    private(set) var jellyRect = CGRect(x: 300, y: 60, width: 260, height: 170)
    private var moodiInside = false

    private static var textures: [String: SKTexture] = [:]
    private static func tex(_ name: String) -> SKTexture {
        if let t = textures[name] { return t }
        let t = SKTexture(imageNamed: name)
        textures[name] = t
        return t
    }

    private var accent: UIColor { world.uiAccent }
    private var pastel: [UIColor] {
        world == .candy
            ? [accent, UIColor(red: 0.8, green: 0.72, blue: 1, alpha: 1), UIColor(red: 1, green: 0.88, blue: 0.55, alpha: 1),
               UIColor(red: 0.62, green: 0.92, blue: 0.8, alpha: 1), .white]
            : [accent, UIColor(red: 0.86, green: 1, blue: 0.55, alpha: 1), UIColor(red: 1, green: 0.95, blue: 0.75, alpha: 1), .white]
    }

    init(world: MoodWorld) {
        self.world = world
        super.init(size: CGSize(width: 844, height: 390))
        backgroundColor = .clear
        scaleMode = .resizeFill
        anchorPoint = .zero
        physicsWorld.contactDelegate = self
        physicsWorld.gravity = CGVector(dx: 0, dy: -4)
        addChild(ambientLayer)
        addChild(moteLayer)
        addChild(fxLayer)
        ambientLayer.zPosition = 0
        moteLayer.zPosition = 20
        fxLayer.zPosition = 30

        moodiShadow.color = UIColor(red: 0.72, green: 0.6, blue: 1, alpha: 1)
        moodiShadow.colorBlendFactor = 1
        moodiShadow.blendMode = .add
        moodiShadow.alpha = 0
        moodiShadow.zPosition = 9
        addChild(moodiShadow)
        moodi.zPosition = 10
        moodi.alpha = 0
        addChild(moodi)

        buildAmbient()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        let edge = SKPhysicsBody(edgeLoopFrom: CGRect(origin: .zero, size: size))
        edge.categoryBitMask = Category.edge
        edge.restitution = 0.9
        edge.friction = 0.05
        physicsBody = edge
        layoutAmbient()
    }

    /// Pillow rect from the 3D stage, in UIKit points.
    func setJellyRect(_ uiRect: CGRect) {
        jellyRect = CGRect(x: uiRect.minX, y: size.height - uiRect.maxY, width: uiRect.width, height: uiRect.height)
        if moodiInside, moodi.action(forKey: "move") == nil { moodi.position = insidePoint }
    }

    private var insidePoint: CGPoint { CGPoint(x: jellyRect.midX, y: jellyRect.minY + jellyRect.height * 0.5) }
    private var jellyTop: CGPoint { CGPoint(x: jellyRect.midX, y: jellyRect.maxY) }

    func toScene(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: size.height - p.y) }

    // MARK: - Squeeze burst

    func burst(intensity: Double, side: Double) {
        let i = CGFloat(intensity)
        let origin = mouthPoint ?? CGPoint(x: jellyRect.midX + CGFloat(side) * jellyRect.width * 0.18, y: jellyRect.maxY - jellyRect.height * 0.12)

        // Soft ring + glow flash
        flash(at: origin, texture: "fx_ring", from: 0.15, to: 0.8 + 0.6 * i, duration: 0.45, alpha: 0.45, color: accent)
        flash(at: origin, texture: "fx_glow", from: 0.4, to: 1.0 + 0.5 * i, duration: 0.3, alpha: 0.38, color: accent)

        // The world's own 3D props (SoftStage.burst) are what flies out; here only a few small glints,
        // biased up and away from the pressed side, bouncing off the screen edges.
        let up = CGFloat.pi / 2 - CGFloat(side) * 0.45
        for _ in 0..<scaled(3 + Int(4 * i)) {
            sparkOut(texture: "fx_sparkle", at: origin, angle: up + .random(in: -0.55 * .pi ... 0.55 * .pi),
                     speed: 260 + 260 * i + .random(in: -110...110), scale: 0.12 + .random(in: -0.035...0.035),
                     life: .random(in: 1.1...1.8), spin: .random(in: -2...2), color: accent, tintFrom: 0)
        }
    }

    /// A gift milestone (20 / 50 / 80 %): a bigger double ring and a shower of stars.
    func giftBurst(at uiPoint: CGPoint? = nil) {
        let origin = uiPoint.map { toScene($0) } ?? mouthPoint ?? CGPoint(x: jellyRect.midX, y: jellyRect.maxY)
        flash(at: origin, texture: "fx_splash", from: 0.3, to: 2.2, duration: 0.7, alpha: 0.9, color: accent)
        run(.wait(forDuration: 0.12)) { [weak self] in
            guard let self else { return }
            self.flash(at: origin, texture: "fx_splash", from: 0.3, to: 2.6, duration: 0.7, alpha: 0.6, color: .white)
        }
        for _ in 0..<scaled(8) {
            sparkOut(texture: "fx_sparkle", at: origin, angle: .pi / 2 + .random(in: -0.7 * .pi ... 0.7 * .pi),
                     speed: 480 + .random(in: -100...100), scale: 0.07 + .random(in: -0.015...0.015),
                     life: .random(in: 1.6...2.3), spin: 2.5, color: accent, tintFrom: 0)
        }
    }

    /// Completion confetti: beads and stars rain from the top edge.
    func celebrate() {
        let ring = mouthPoint ?? CGPoint(x: jellyRect.midX, y: jellyRect.midY)
        flash(at: ring, texture: "fx_ring", from: 0.2, to: 4, duration: 0.9, alpha: 0.9, color: accent)
        flash(at: ring, texture: "fx_glow", from: 0.5, to: 5, duration: 0.8, alpha: 0.9, color: .white)
    }

    // MARK: - Edge hits

    /// Something hit the screen edge here (scene coordinates): flare the edge and splash.
    func edgeSplash(at point: CGPoint, strength: Double) {
        let s = CGFloat(min(1, max(0.15, strength)))
        let w = size.width, h = size.height
        let distances: [(CGFloat, Int)] = [(point.x, 0), (w - point.x, 1), (point.y, 2), (h - point.y, 3)]
        let edge = distances.min { $0.0 < $1.0 }!.1
        var p = point
        let inward: CGFloat
        switch edge {
        case 0: p.x = 0; inward = 0
        case 1: p.x = w; inward = .pi
        case 2: p.y = 0; inward = .pi / 2
        default: p.y = h; inward = -.pi / 2
        }

        // Glow streak along the edge
        let streak = SKSpriteNode(texture: Self.tex("fx_glow"))
        let horizontal = edge >= 2
        streak.size = horizontal ? CGSize(width: 120 + 220 * s, height: 26 + 20 * s) : CGSize(width: 26 + 20 * s, height: 120 + 220 * s)
        streak.position = p
        streak.color = accent
        streak.colorBlendFactor = 0.7
        streak.blendMode = .add
        streak.alpha = 0.9 * s + 0.1
        fxLayer.addChild(streak)
        streak.run(.sequence([.group([.fadeOut(withDuration: 0.55), .scaleX(by: horizontal ? 1.3 : 1, y: horizontal ? 1 : 1.3, duration: 0.55)]), .removeFromParent()]))

        // Splash ring
        flash(at: p, texture: "fx_splash", from: 0.1, to: 0.35 + 0.45 * s, duration: 0.45, alpha: 0.85, color: accent)

        // A few sparks thrown back into the screen
        let sparks = emitter("fx_sparkle", count: 1 + Int(3 * s))
        sparks.position = p
        sparks.emissionAngle = inward
        sparks.emissionAngleRange = .pi * 0.7
        sparks.particleSpeed = 160 + 160 * s
        sparks.particleSpeedRange = 80
        sparks.particleLifetime = 0.5
        sparks.particleScale = 0.08
        sparks.particleScaleSpeed = -0.12
        sparks.particleAlphaSpeed = -1.6
        sparks.particleColorSequence = SKKeyframeSequence(keyframeValues: [UIColor.white, accent], times: [0, 0.4])
        fire(sparks, lifetime: 0.9)
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let mask = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        guard mask & Category.edge != 0, mask & Category.mote != 0 else { return }
        let strength = Double(min(1, contact.collisionImpulse / 0.06))
        guard strength > 0.2 else { return }
        let now = CACurrentMediaTime()
        guard now - lastSplash > 0.035 else { return }
        lastSplash = now
        edgeSplash(at: contact.contactPoint, strength: strength * 0.6)
        onMoteEdgeHit?(contact.contactPoint, strength)
    }

    // MARK: - Bouncing sparks

    /// Squeeze sparkles and stars: moved by hand each frame so they can bounce off the screen
    /// edges (emitter particles can't collide), slowing a little with every bounce.
    private struct Spark {
        let node: SKSpriteNode
        var velocity: CGVector
        var age: Double = 0
        let life: Double
        let spin: CGFloat
        let scale: CGFloat
        let tintFrom: CGFloat
    }
    private let sparkLayer = SKNode()
    private var sparks: [Spark] = []
    private var lastUpdate: TimeInterval?

    private func scaled(_ count: Int) -> Int {
        Int((Double(count) * (UIAccessibility.isReduceMotionEnabled ? 0.35 : 0.75)).rounded())
    }

    private func sparkOut(texture: String, at p: CGPoint, angle: CGFloat, speed: CGFloat, scale: CGFloat,
                          life: Double, spin: CGFloat, color: UIColor, tintFrom: CGFloat) {
        if sparkLayer.parent == nil { sparkLayer.zPosition = 25; addChild(sparkLayer) }
        if sparks.count >= 160 { sparks.removeFirst().node.removeFromParent() }
        let node = SKSpriteNode(texture: Self.tex(texture))
        node.setScale(max(0.02, scale))
        node.position = p
        node.zRotation = .random(in: 0...(.pi * 2))
        node.color = color
        node.colorBlendFactor = tintFrom
        node.blendMode = .add
        sparkLayer.addChild(node)
        sparks.append(Spark(node: node, velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                            life: life, spin: spin, scale: max(0.02, scale), tintFrom: tintFrom))
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = min(1.0 / 30, max(0, currentTime - (lastUpdate ?? currentTime)))
        lastUpdate = currentTime
        guard !sparks.isEmpty else { return }
        let ax = gravity.dx * 420, ay = gravity.dy * 420
        let drag = 1 - 0.5 * CGFloat(dt)
        var i = 0
        while i < sparks.count {
            var s = sparks[i]
            s.age += dt
            if s.age >= s.life {
                s.node.removeFromParent()
                sparks.remove(at: i)
                continue
            }
            s.velocity.dx = (s.velocity.dx + ax * CGFloat(dt)) * drag
            s.velocity.dy = (s.velocity.dy + ay * CGFloat(dt)) * drag
            var p = s.node.position
            p.x += s.velocity.dx * CGFloat(dt)
            p.y += s.velocity.dy * CGFloat(dt)
            // bounce: off any screen edge, losing a third of the speed
            let r = s.node.frame.width * 0.3
            if p.x < r { p.x = r; s.velocity.dx = abs(s.velocity.dx) * 0.65 }
            if p.x > size.width - r { p.x = size.width - r; s.velocity.dx = -abs(s.velocity.dx) * 0.65 }
            if p.y < r { p.y = r; s.velocity.dy = abs(s.velocity.dy) * 0.6 }
            if p.y > size.height - r { p.y = size.height - r; s.velocity.dy = -abs(s.velocity.dy) * 0.65 }
            s.node.position = p
            s.node.zRotation += s.spin * CGFloat(dt)
            let k = CGFloat(s.age / s.life)
            s.node.alpha = k < 0.6 ? 1 : (1 - k) / 0.4
            s.node.setScale(s.scale * (1 - 0.45 * k))
            if s.tintFrom < 1 { s.node.colorBlendFactor = min(1, k / 0.35) }
            sparks[i] = s
            i += 1
        }
    }

    // MARK: - Flow (free mode, rocking the bag)

    private var flowEmitter: SKEmitterNode?

    /// While the bag is rocking, a soft stream of light rises out of the pillow, as strong as the rocking.
    func setFlow(_ level: Double) {
        if flowEmitter == nil {
            guard level > 0.02 else { return }
            let e = emitter("fx_sparkle", count: 0)
            e.particleBirthRate = 0
            e.particleLifetime = 1.3
            e.particleLifetimeRange = 0.5
            e.emissionAngle = .pi / 2
            e.emissionAngleRange = .pi * 0.55
            e.particleSpeed = 120
            e.particleSpeedRange = 70
            e.yAcceleration = -60
            e.particleScale = 0.09
            e.particleScaleRange = 0.04
            e.particleScaleSpeed = -0.04
            e.particleRotationSpeed = 2
            e.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.95, 0] as [NSNumber], times: [0, 0.25, 1])
            e.particleColorSequence = SKKeyframeSequence(keyframeValues: [UIColor.white, accent], times: [0, 0.6])
            e.targetNode = fxLayer
            e.zPosition = 5
            fxLayer.addChild(e)
            flowEmitter = e
        }
        guard let e = flowEmitter else { return }
        let origin = mouthPoint ?? CGPoint(x: jellyRect.midX, y: jellyRect.maxY - jellyRect.height * 0.15)
        e.position = origin
        e.particlePositionRange = CGVector(dx: jellyRect.width * 0.35, dy: 6)
        let calm = UIAccessibility.isReduceMotionEnabled ? 0.35 : 1
        e.particleBirthRate = CGFloat(level < 0.03 ? 0 : 2 + 12 * level * calm)
        e.particleSpeed = CGFloat(90 + 140 * level)
    }

    // MARK: - Bouncy motes

    private func spawnMote(at p: CGPoint, velocity: CGVector) {
        if moteLayer.children.count > 36 { moteLayer.children.first?.removeFromParent() }
        let names = world == .candy ? ["fx_sugar"] : ["fx_leaf2", "fx_leaf3"]
        let name = names.randomElement()!
        let d = CGFloat.random(in: 15...27)
        let node = SKSpriteNode(texture: Self.tex(name))
        node.size = CGSize(width: d, height: d)
        let isLeaf = name.hasPrefix("fx_leaf")
        if !isLeaf {
            node.color = pastel.randomElement()!
            node.colorBlendFactor = name == "fx_seed" ? 0.25 : 0.85
            let glow = SKSpriteNode(texture: Self.tex("fx_glow"))
            glow.size = CGSize(width: d * 2.4, height: d * 2.4)
            glow.color = node.color
            glow.colorBlendFactor = 1
            glow.blendMode = .add
            glow.alpha = 0.45
            glow.zPosition = -1
            node.addChild(glow)
        }
        node.position = CGPoint(x: min(max(p.x, d), size.width - d), y: min(max(p.y, d), size.height - d))
        node.zRotation = .random(in: 0...(.pi * 2))

        let body = SKPhysicsBody(circleOfRadius: d * 0.36)
        body.categoryBitMask = Category.mote
        body.collisionBitMask = Category.edge
        body.contactTestBitMask = Category.edge
        body.restitution = 0.86
        body.friction = 0.05
        body.linearDamping = 0.18
        body.angularDamping = 0.4
        body.mass = 0.02
        body.velocity = velocity
        body.angularVelocity = .random(in: -7...7)
        node.physicsBody = body
        moteLayer.addChild(node)

        node.run(.sequence([.wait(forDuration: 4 + .random(in: 0...1.6)),
                            .group([.fadeOut(withDuration: 0.6), .scale(to: 0.3, duration: 0.6)]),
                            .removeFromParent()]))
    }

    // MARK: - Ambient (grows with energy)

    private func buildAmbient() {
        switch world {
        case .candy:
            let dust = emitter("fx_mote", count: 0)
            dust.particleBirthRate = 0
            dust.particleLifetime = 11
            dust.particleLifetimeRange = 4
            dust.emissionAngle = -.pi / 2
            dust.emissionAngleRange = 0.6
            dust.particleSpeed = 26
            dust.particleSpeedRange = 16
            dust.particleScale = 0.07
            dust.particleScaleRange = 0.04
            dust.particleAlpha = 0.75
            dust.particleAlphaRange = 0.25
            dust.particleColor = UIColor(red: 1, green: 0.9, blue: 0.96, alpha: 1)
            dust.particleColorBlendFactor = 1
            dust.particleBlendMode = .add
            ambientLayer.addChild(dust)
            ambient.append((dust, 40))

            let twinkle = emitter("fx_twinkle", count: 0)
            twinkle.particleBirthRate = 0
            twinkle.particleLifetime = 2.2
            twinkle.particleLifetimeRange = 0.8
            twinkle.emissionAngleRange = .pi * 2
            twinkle.particleSpeed = 8
            twinkle.particleScale = 0.07
            twinkle.particleScaleRange = 0.04
            twinkle.particleRotationSpeed = 1
            twinkle.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 1, 0] as [NSNumber], times: [0, 0.4, 1])
            twinkle.particleColor = .white
            ambientLayer.addChild(twinkle)
            ambient.append((twinkle, 4))
        case .nature:
            for name in ["fx_leaf1", "fx_leaf2", "fx_leaf3"] {
                let leaf = emitter(name, count: 0)
                leaf.particleBirthRate = 0
                leaf.particleLifetime = 12
                leaf.particleLifetimeRange = 3
                leaf.emissionAngle = -.pi / 2
                leaf.emissionAngleRange = 0.7
                leaf.particleSpeed = 46
                leaf.particleSpeedRange = 22
                leaf.particleScale = 0.11
                leaf.particleScaleRange = 0.05
                leaf.particleRotationRange = .pi * 2
                leaf.particleRotationSpeed = 0.9
                leaf.particleAlpha = 0.95
                leaf.particleColorBlendFactor = 0
                leaf.particleBlendMode = .alpha
                ambientLayer.addChild(leaf)
                ambient.append((leaf, 1.8))
            }
            let flies = emitter("fx_glow", count: 0)
            flies.particleBirthRate = 0.6
            flies.particleLifetime = 5.5
            flies.particleLifetimeRange = 2.5
            flies.emissionAngleRange = .pi * 2
            flies.particleSpeed = 12
            flies.particleSpeedRange = 10
            flies.particleScale = 0.05
            flies.particleScaleRange = 0.03
            flies.particleColor = UIColor(red: 0.88, green: 1, blue: 0.5, alpha: 1)
            flies.particleColorBlendFactor = 1
            flies.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.95, 0.3, 0.9, 0] as [NSNumber], times: [0, 0.25, 0.5, 0.7, 1])
            ambientLayer.addChild(flies)
            fireflies = flies
            ambient.append((flies, 8))
        }
        setEnergy(0)
    }

    private func layoutAmbient() {
        for (node, _) in ambient {
            if node === fireflies {
                node.position = CGPoint(x: size.width / 2, y: size.height * 0.4)
                node.particlePositionRange = CGVector(dx: size.width, dy: size.height * 0.8)
            } else if node.emissionAngleRange >= .pi * 2 - 0.01 {
                node.position = CGPoint(x: size.width / 2, y: size.height / 2)
                node.particlePositionRange = CGVector(dx: size.width, dy: size.height)
            } else {
                node.position = CGPoint(x: size.width / 2, y: size.height + 20)
                node.particlePositionRange = CGVector(dx: size.width * 1.2, dy: 0)
            }
        }
    }

    /// CandyFrostParticleController: 0–20 % almost nothing, 20–50 % soft dust, 50–100 % a
    /// real snowfall with sparkles, switching to a dense fall near 100 %.
    func setEnergy(_ e: Double) {
        energy = e
        let dust = e < 0.2 ? e / 0.2 * 0.035 : 0.035 + (1 - 0.035) * smooth((e - 0.2) / 0.8)
        let sparkle = smooth((e - 0.5) / 0.5)
        let full = smooth((e - 0.82) / 0.18)
        for (index, (node, maxRate)) in ambient.enumerated() {
            if node === fireflies {
                node.particleBirthRate = CGFloat(0.6 + (maxRate - 0.6) * smooth(e / 0.9))
            } else if world == .candy && index == 1 {
                node.particleBirthRate = CGFloat(maxRate * sparkle)
            } else if world == .candy {
                node.particleBirthRate = CGFloat(maxRate * dust + 40 * full)
            } else {
                node.particleBirthRate = CGFloat(0.08 + maxRate * dust + 1.2 * full)
            }
        }
    }

    private func smooth(_ x: Double) -> Double {
        let t = max(0, min(1, x))
        return t * t * (3 - 2 * t)
    }

    /// Screen-space gravity from the phone (x right, y up, in g).
    func setGravity(_ g: CGVector) {
        gravity = g
        physicsWorld.gravity = CGVector(dx: g.dx * 6, dy: g.dy * 6)
        for (node, _) in ambient where node !== fireflies {
            node.xAcceleration = g.dx * 60 + (world == .nature ? 6 : 0)
            node.yAcceleration = (g.dy + 0.75) * 30
        }
    }

    /// A shake sends every bead flying.
    func scatter() {
        for case let node as SKSpriteNode in moteLayer.children {
            node.physicsBody?.applyImpulse(CGVector(dx: .random(in: -14...14), dy: .random(in: 4...16)))
        }
    }

    // MARK: - Moodi

    /// Moodi flies in, waves above the pillow, slips and sinks into it.
    /// `onSplash` fires when Moodi lands in the jelly.
    func moodiFallIn(onSplash: @escaping () -> Void) {
        guard spriteMoodi else { return }
        moodi.removeAllActions()
        moodiShadow.removeAllActions()
        moodiInside = false
        moodi.texture = Self.tex("moodi_happy")
        moodi.size = CGSize(width: 96, height: 96)
        moodi.alpha = 1
        moodi.colorBlendFactor = 0
        moodi.zRotation = 0
        moodi.setScale(1)
        moodi.position = CGPoint(x: size.width + 70, y: size.height * 0.92)
        moodiShadow.alpha = 0

        let hover = CGPoint(x: jellyRect.midX + 20, y: jellyRect.maxY + 70)
        let path = UIBezierPath()
        path.move(to: moodi.position)
        path.addCurve(to: hover, controlPoint1: CGPoint(x: size.width * 0.85, y: size.height * 1.05),
                      controlPoint2: CGPoint(x: hover.x + 160, y: hover.y + 90))
        let fly = SKAction.follow(path.cgPath, asOffset: false, orientToPath: false, duration: 0.9)
        fly.timingMode = .easeOut
        let wave = SKAction.sequence([.rotate(toAngle: 0.18, duration: 0.15), .rotate(toAngle: -0.12, duration: 0.15),
                                      .rotate(toAngle: 0.12, duration: 0.15), .rotate(toAngle: 0, duration: 0.12)])
        let slip = SKAction.group([.rotate(toAngle: 0.6, duration: 0.12),
                                   .run { [weak self] in self?.moodi.texture = Self.tex("moodi_tense") }])
        let drop = SKAction.move(to: insidePoint, duration: 0.32)
        drop.timingMode = .easeIn
        let sink = SKAction.group([
            .rotate(toAngle: 0, duration: 0.25),
            .resize(toWidth: 78, height: 78, duration: 0.25),
            .fadeAlpha(to: 0.45, duration: 0.3),
            .colorize(with: accent, colorBlendFactor: 0.45, duration: 0.3),
            .sequence([.scaleX(to: 1.25, y: 0.75, duration: 0.08), .scaleX(to: 0.9, y: 1.1, duration: 0.1), .scale(to: 1, duration: 0.12)]),
        ])
        moodi.run(.sequence([fly, wave, .wait(forDuration: 0.15), slip, drop,
                             .run { [weak self] in
                                 guard let self else { return }
                                 self.moodiInside = true
                                 self.splash(at: self.insidePoint)
                                 onSplash()
                             },
                             sink,
                             .run { [weak self] in self?.startInsideIdle() }]), withKey: "move")
    }

    private func startInsideIdle() {
        let bob = SKAction.sequence([.moveBy(x: 0, y: 5, duration: 1.3), .moveBy(x: 0, y: -5, duration: 1.3)])
        bob.timingMode = .easeInEaseOut
        let sway = SKAction.sequence([.rotate(toAngle: 0.07, duration: 1.6), .rotate(toAngle: -0.07, duration: 1.6)])
        moodi.run(.repeatForever(.group([bob, sway])), withKey: "idle")
        moodiShadow.position = insidePoint
        moodiShadow.size = CGSize(width: 150, height: 150)
        moodiShadow.run(.fadeAlpha(to: 0.25, duration: 0.6))
    }

    /// Moodi gets clearer and happier as the energy rises.
    func moodiReact(energy e: Double, intensity: Double) {
        guard spriteMoodi else { return }
        guard moodiInside else { return }
        let face = e < 0.5 ? "moodi_tense" : (e < 0.8 ? "moodi_neutral" : "moodi_happy")
        moodi.texture = Self.tex(face)
        moodi.run(.group([.fadeAlpha(to: CGFloat(0.45 + 0.45 * e), duration: 0.3),
                          .colorize(with: accent, colorBlendFactor: CGFloat(0.45 * (1 - e)), duration: 0.3)]))
        let i = CGFloat(intensity)
        let wiggle = SKAction.sequence([.scaleX(to: 1 + 0.22 * i, y: 1 - 0.18 * i, duration: 0.07),
                                        .scaleX(to: 1 - 0.08 * i, y: 1 + 0.1 * i, duration: 0.1),
                                        .scale(to: 1, duration: 0.14)])
        moodi.run(wiggle, withKey: "wiggle")
        moodiShadow.run(.fadeAlpha(to: CGFloat(0.25 + 0.5 * e), duration: 0.3))
    }

    /// Is this UIKit point on the 2D Moodi?
    func spriteMoodiHit(_ uiPoint: CGPoint) -> Bool {
        guard spriteMoodi, moodi.alpha > 0.2, moodi.parent != nil else { return false }
        let p = toScene(uiPoint)
        return hypot(p.x - moodi.position.x, p.y - moodi.position.y) < max(40, moodi.size.width * 0.6)
    }

    /// A finger poked the 2D Moodi: squish, giggle and a few sparkles.
    func moodiPoke() {
        guard spriteMoodi else { return }
        let squish = SKAction.sequence([.scaleX(to: 1.25, y: 0.78, duration: 0.08), .scaleX(to: 0.9, y: 1.14, duration: 0.1),
                                        .scaleX(to: 1.05, y: 0.96, duration: 0.1), .scale(to: 1, duration: 0.12)])
        moodi.run(squish, withKey: "poke")
        flash(at: moodi.position, texture: "fx_splash", from: 0.2, to: 1.1, duration: 0.4, alpha: 0.7, color: accent)
    }

    /// Little hearts / sparkles over the 3D Moodi when poked (UIKit point).
    func pokeSparkle(at uiPoint: CGPoint) {
        let p = toScene(uiPoint)
        flash(at: p, texture: "fx_splash", from: 0.2, to: 1.0, duration: 0.4, alpha: 0.6, color: accent)
        let e = emitter("fx_sparkle", count: 6)
        e.position = p
        e.emissionAngle = .pi / 2
        e.emissionAngleRange = .pi * 0.9
        e.particleSpeed = 220
        e.particleSpeedRange = 80
        e.particleLifetime = 0.9
        e.particleScale = 0.05
        e.particleAlphaSpeed = -1
        e.yAcceleration = -260
        e.particleColorSequence = SKKeyframeSequence(keyframeValues: [UIColor.white, accent], times: [0, 0.6])
        fire(e, lifetime: 1.2)
    }

    /// The pillow pops and Moodi jumps out, spins and floats in front of you.
    func moodiPopOut() {
        guard spriteMoodi else { return }
        moodi.removeAction(forKey: "idle")
        moodiInside = false
        moodi.texture = Self.tex("moodi_happy")
        let target = CGPoint(x: jellyRect.midX, y: jellyRect.midY + jellyRect.height * 0.25)
        let jump = SKAction.move(to: CGPoint(x: target.x, y: target.y + 70), duration: 0.38)
        jump.timingMode = .easeOut
        let land = SKAction.move(to: target, duration: 0.3)
        land.timingMode = .easeInEaseOut
        moodi.run(.sequence([
            .group([.fadeAlpha(to: 1, duration: 0.15), .colorize(withColorBlendFactor: 0, duration: 0.15),
                    .resize(toWidth: 132, height: 132, duration: 0.38), jump, .rotate(byAngle: .pi * 2, duration: 0.5)]),
            land,
            .run { [weak self] in
                let bob = SKAction.sequence([.moveBy(x: 0, y: 8, duration: 0.9), .moveBy(x: 0, y: -8, duration: 0.9)])
                bob.timingMode = .easeInEaseOut
                self?.moodi.run(.repeatForever(bob), withKey: "idle")
            },
        ]), withKey: "move")
        moodiShadow.run(.fadeOut(withDuration: 0.3))
    }

    /// Moodi floats away (before a replay or on exit).
    func moodiLeave() {
        guard spriteMoodi else { return }
        moodi.removeAllActions()
        moodiInside = false
        moodi.run(.group([.moveBy(x: 0, y: 160, duration: 0.5), .fadeOut(withDuration: 0.4)]))
        moodiShadow.run(.fadeOut(withDuration: 0.3))
    }

    func splash(at p: CGPoint) {
        flash(at: p, texture: "fx_splash", from: 0.2, to: 1.4, duration: 0.5, alpha: 0.9, color: accent)
        let drops = emitter(world == .candy ? "fx_sugar" : "fx_leaf2", count: 8)
        drops.position = p
        drops.emissionAngle = .pi / 2
        drops.emissionAngleRange = .pi * 0.8
        drops.particleSpeed = 300
        drops.particleSpeedRange = 120
        drops.particleLifetime = 1.0
        drops.particleScale = 0.1
        drops.particleScaleRange = 0.05
        drops.particleAlphaSpeed = -0.9
        drops.yAcceleration = -700
        drops.particleColor = pastel.randomElement()!
        fire(drops, lifetime: 1.4)
    }

    // MARK: - Helpers

    private func emitter(_ texture: String, count: Int) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = Self.tex(texture)
        // a little lighter than the visionOS counts (the phone screen is small), much lighter with Reduce Motion
        let n = count > 0 ? max(1, Int((Double(count) * (UIAccessibility.isReduceMotionEnabled ? 0.35 : 0.75)).rounded())) : 0
        e.numParticlesToEmit = n
        e.particleBirthRate = n > 0 ? 800 : 0
        e.particleColorBlendFactor = 1
        e.particleColor = .white
        e.particleBlendMode = .add
        e.particleAlpha = 1
        return e
    }

    private func fire(_ emitter: SKEmitterNode, lifetime: TimeInterval) {
        emitter.targetNode = fxLayer
        fxLayer.addChild(emitter)
        emitter.run(.sequence([.wait(forDuration: lifetime), .removeFromParent()]))
    }

    private func flash(at p: CGPoint, texture: String, from: CGFloat, to: CGFloat, duration: TimeInterval, alpha: CGFloat, color: UIColor) {
        let node = SKSpriteNode(texture: Self.tex(texture))
        node.size = CGSize(width: 160, height: 160)
        node.position = p
        node.setScale(from)
        node.alpha = alpha
        node.color = color
        node.colorBlendFactor = 1
        node.blendMode = .add
        fxLayer.addChild(node)
        let grow = SKAction.scale(to: to, duration: duration)
        grow.timingMode = .easeOut
        node.run(.sequence([.group([grow, .fadeOut(withDuration: duration)]), .removeFromParent()]))
    }
}
