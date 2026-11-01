import SwiftUI
import SceneKit

/// The animated 3D Moodi (Moodi.usdz + the baked clips in CandySoft_MoodiTracks.json) standing
/// on its own: Idle in a loop, a Wave when it first appears, Touched when poked.
final class MoodiFigureModel: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let camera = SCNNode()
    private let holder = SCNNode()
    private var rig: BoneRig?
    private var eyes: [(Int, Int)] = []
    private let lock = NSLock()
    private var clock: Float = 0
    private var lastTime: TimeInterval = 0
    private var waveAt: Float? = 0.4
    private var touchAt: Float?
    private var blinkAt: Float = 2
    private(set) var ready = false

    override init() {
        super.init()
        let cam = SCNCamera()
        cam.fieldOfView = 30
        camera.camera = cam
        camera.position = SCNVector3(0, 0.05, 4.9)
        scene.rootNode.addChildNode(camera)
        scene.background.contents = UIColor.clear
        if let pano = Res.image("pano_candy") {
            scene.lightingEnvironment.contents = pano
            scene.lightingEnvironment.intensity = 0.75
        }
        let key = SCNNode()
        key.light = SCNLight(); key.light?.type = .directional; key.light?.intensity = 260
        key.eulerAngles = SCNVector3(-0.5, 0.4, 0)
        scene.rootNode.addChildNode(key)
        scene.rootNode.addChildNode(holder)
        load()
    }

    private func load() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let url = Res.url("Moodi", "usdz"), let tracksURL = Res.url("CandySoft_MoodiTracks", "json"),
                  let source = try? SCNScene(url: url, options: [.checkConsistency: false]),
                  let data = try? Data(contentsOf: tracksURL),
                  let tracks = try? JSONDecoder().decode(MoodiTracks.self, from: data) else { return }
            let body = SCNNode()
            for child in source.rootNode.childNodes { body.addChildNode(child) }
            let rig = BoneRig(tracks.moodi, fps: tracks.fps, under: body)
            guard rig.missingBones.isEmpty else { return }
            let eyes: [(Int, Int)] = ["Eye_L", "Eye_R"].compactMap { name in
                guard let k = rig.boneIndex(name) else { return nil }
                let r = rig.restRotation(name)
                return (k, abs(r.act(SIMD3(1, 0, 0)).z) > abs(r.act(SIMD3(0, 0, 1)).z) ? 0 : 2)
            }
            rig.apply(rig.sample("Idle", frame: 0))
            DispatchQueue.main.async {
                guard let self else { return }
                self.lock.lock()
                self.rig = rig; self.eyes = eyes
                // Moodi is 1.83 rig units tall, feet near the origin: centre it in view.
                body.position = SCNVector3(0, 0, 0)
                body.scale = SCNVector3(1, 1, 1)
                self.holder.addChildNode(body)
                self.holder.opacity = 0
                self.holder.runAction(.fadeIn(duration: 0.35))
                self.ready = true
                self.lock.unlock()
            }
        }
    }

    /// A poke: Touched over Idle (about 0.9 s). Returns false while the last poke is still playing.
    func poke() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let rig else { return false }
        if let t = touchAt, clock - t < rig.duration("Touched") * 0.6 { return false }
        touchAt = clock
        blinkAt = clock + 0.05
        return true
    }

    func wave() { lock.lock(); waveAt = clock; lock.unlock() }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = Float(min(1.0 / 20, lastTime == 0 ? 1.0 / 60 : time - lastTime))
        lastTime = time
        lock.lock(); defer { lock.unlock() }
        guard let rig else { return }
        clock += dt
        var pose = rig.sample("Idle", time: clock, loop: true)
        if let w = waveAt {
            let d = clock - w, len = rig.duration("Wave")
            if d >= len { waveAt = nil } else { pose = mixPose(pose, rig.sample("Wave", time: d, loop: false), min(1, d / 0.15) * min(1, (len - d) / 0.2)) }
        }
        if let t = touchAt {
            let d = clock - t, len = rig.duration("Touched")
            if d >= len { touchAt = nil } else { pose = mixPose(pose, rig.sample("Touched", time: d, loop: false), min(1, d / 0.1) * min(1, (len - d) / 0.15)) }
        }
        // blink every few seconds
        let b = clock - blinkAt
        if b > 0.2 { blinkAt = clock + Float.random(in: 2.5...5) }
        if b >= 0, b < 0.2 {
            let closed: Float = 0.08
            let a = b < 0.1 ? 1 - (1 - closed) * (b / 0.1) : closed + (1 - closed) * ((b - 0.1) / 0.1)
            for (k, axis) in eyes { pose[k].s[axis] *= a }
        }
        rig.apply(pose)
        // a gentle turn so it feels alive
        holder.eulerAngles.y = 0.18 * sin(clock * 0.6)
    }
}

/// SwiftUI host: transparent SCNView; a tap pokes Moodi.
struct MoodiFigure: UIViewRepresentable {
    let model: MoodiFigureModel
    var onPoke: () -> Void = {}

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = model.scene
        view.pointOfView = model.camera
        view.delegate = model
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isPlaying = true
        view.rendersContinuously = true
        view.antialiasingMode = .multisampling4X
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap)))
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) { context.coordinator.parent = self }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: MoodiFigure
        init(_ parent: MoodiFigure) { self.parent = parent }
        @objc func tap() { if parent.model.poke() { parent.onPoke() } }
    }
}
