import SceneKit
import SwiftUI

/// 3D world carousel, ported from WorldCarouselSelectionController / WorldCarouselLayout:
/// side worlds shrink to 70 %, fade to 55 %, turn 20° toward the centre and sit slightly back;
/// switching eases out (cubic) over 0.35 s.
final class CarouselStage: NSObject, ObservableObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let camera = SCNNode()

    @Published private(set) var loaded = [false, false]
    @Published private(set) var selection = 0

    private let slots = [SCNNode(), SCNNode()]
    private let spinners = [SCNNode(), SCNNode()]
    private let lock = NSLock()

    // Layout constants (Unity values, spacing re-tuned for a phone screen).
    private let spacing: Float = 2.55
    private let sideScale: Float = 0.7
    private let sideAlpha: Float = 0.55
    private let sideYaw: Float = 20 * .pi / 180
    private let switchSeconds = 0.35

    private var display: Float = 0
    private var from: Float = 0
    private var animStart: TimeInterval = 0
    private var animating = false
    private var drag: Float = 0
    private var entering = -1
    private var enterStart: TimeInterval = 0

    override init() {
        super.init()
        scene.background.contents = UIColor.clear

        let cam = SCNCamera()
        cam.fieldOfView = 30
        cam.wantsHDR = false
        camera.camera = cam
        camera.position = SCNVector3(0, 1.15, 6.4)
        camera.look(at: SCNVector3(0, 0.05, 0))
        scene.rootNode.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 120
        ambient.light?.color = UIColor(red: 1, green: 0.95, blue: 0.97, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 680
        key.eulerAngles = SCNVector3(-0.7, -0.5, 0)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 300
        rim.light?.color = UIColor(red: 0.85, green: 0.78, blue: 1, alpha: 1)
        rim.eulerAngles = SCNVector3(-0.3, .pi * 0.85, 0)
        scene.rootNode.addChildNode(rim)

        setEnvironment(for: .candy)

        for i in 0..<2 {
            slots[i].addChildNode(spinners[i])
            scene.rootNode.addChildNode(slots[i])
        }
        applyLayout(time: 0)
        loadWorlds()
    }

    func setEnvironment(for world: MoodWorld) {
        // The world panorama lights the PBR islands so they pick up its colours.
        scene.lightingEnvironment.contents = Res.image(world.panorama)
        scene.lightingEnvironment.intensity = 0.95
    }

    private func loadWorlds() {
        for world in MoodWorld.allCases {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let loaded = ModelLoader.load(world.islandModel, extent: 2.2, pitch: -.pi / 2) else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    let node = loaded.node
                    node.opacity = 0
                    node.scale = SCNVector3(0.85, 0.85, 0.85)
                    self.spinners[world.index].addChildNode(node)
                    let grow = SCNAction.group([.fadeIn(duration: 0.5), .scale(to: 1, duration: 0.6)])
                    grow.timingMode = .easeOut
                    node.runAction(grow)
                    self.loaded[world.index] = true
                }
            }
        }
    }

    // MARK: Input (main thread)

    func select(_ index: Int) {
        let next = max(0, min(1, index))
        lock.lock()
        from = display + drag
        drag = 0
        display = from
        target = Float(next)
        animStart = CACurrentMediaTime()
        animating = true
        lock.unlock()
        let changed = selection != next
        selection = next
        if changed {
            UISelectionFeedbackGenerator().selectionChanged()
            setEnvironment(for: .at(next))
        }
    }

    private var target: Float = 0

    /// `offset` is the drag distance as a fraction of one carousel step.
    func dragChanged(_ offset: Float) {
        lock.lock()
        animating = false
        drag = max(-0.15 - Float(selection), min(1.15 - Float(selection), -offset))
        lock.unlock()
    }

    func dragEnded(_ offset: Float, predicted: Float) {
        // WorldCarouselLayout.ResolveSwipe: past the threshold, step one world in the swipe direction.
        let threshold: Float = 0.12
        var next = selection
        if abs(offset) > threshold || abs(predicted) > 0.45 {
            next = (offset + predicted * 0.3) < 0 ? selection + 1 : selection - 1
        }
        select(next)
    }

    func playEnter(_ index: Int) {
        lock.lock(); entering = index; enterStart = CACurrentMediaTime(); lock.unlock()
    }

    func resetEnter() {
        lock.lock(); entering = -1; lock.unlock()
    }

    // MARK: Per-frame layout (render thread)

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        applyLayout(time: time)
    }

    private func applyLayout(time: TimeInterval) {
        lock.lock()
        if animating {
            let t = min(1, (CACurrentMediaTime() - animStart) / switchSeconds)
            let eased = Float(1 - pow(1 - t, 3))
            display = from + (target - from) * eased
            if t >= 1 { display = target; animating = false }
        }
        let current = display + drag
        let enter = entering
        let enterT = Float(min(1, (CACurrentMediaTime() - enterStart) / 0.7))
        lock.unlock()

        for i in 0..<2 {
            let offset = Float(i) - current
            let a = min(1, abs(offset))
            let slot = slots[i]
            slot.position = SCNVector3(offset * spacing, 0, -a * 0.9)
            slot.eulerAngles.y = -offset * sideYaw
            var scale = 1 + (sideScale - 1) * a
            var alpha = 1 + (sideAlpha - 1) * a
            if enter >= 0 {
                let e = enterT * enterT
                if i == enter { scale *= 1 + 0.9 * e; alpha *= 1 - 0.85 * e } else { alpha *= 1 - e }
            }
            slot.scale = SCNVector3(scale, scale, scale)
            slot.opacity = CGFloat(alpha)

            // Gentle turntable plus a floating bob, like the visionOS world cards.
            let spin = spinners[i]
            spin.eulerAngles.y = Float(time * 0.16) + Float(i) * 1.7
            spin.position.y = 0.05 * Float(sin(time * 1.1 + Double(i) * 1.3))
        }
    }
}

/// Transparent SceneKit view for the carousel.
struct CarouselView: UIViewRepresentable {
    let stage: CarouselStage

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.scene = stage.scene
        view.pointOfView = stage.camera
        view.delegate = stage
        view.isPlaying = true
        view.rendersContinuously = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}
}
