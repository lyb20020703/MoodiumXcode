import SceneKit
import SwiftUI

/// Above the iPhone Duo's fold: the stage's own panorama, seen from the same spot with the
/// camera tilted up just enough that its bottom edge meets the stage's top edge. Both use the
/// same focal length, so the sky over the stage and the sky above the fold read as one tall
/// picture, and the panorama turns with the phone in both.
struct PanoramaSky: UIViewRepresentable {
    let stage: SoftStage
    /// Height of the stage view right below, in points.
    let stageHeight: CGFloat

    func makeUIView(context: Context) -> PanoramaSkyView { PanoramaSkyView(stage: stage) }

    func updateUIView(_ view: PanoramaSkyView, context: Context) { view.stageHeight = stageHeight }
}

final class PanoramaSkyView: UIView, SCNSceneRendererDelegate {
    private let sceneView = SCNView(frame: .zero)
    private let scene = SCNScene()
    private let cameraNode = SCNNode()
    private weak var stage: SoftStage?
    var stageHeight: CGFloat = 0 { didSet { if stageHeight != oldValue { setNeedsLayout() } } }

    init(stage: SoftStage) {
        self.stage = stage
        super.init(frame: .zero)
        backgroundColor = .black
        isUserInteractionEnabled = false

        scene.background.contents = Res.image(stage.world.panorama)
        let camera = SCNCamera()
        // the same tone mapping and bloom as the stage camera, so the colours match at the seam
        if let c = stage.cameraNode.camera {
            camera.wantsHDR = c.wantsHDR
            camera.bloomIntensity = c.bloomIntensity
            camera.bloomThreshold = c.bloomThreshold
            camera.wantsExposureAdaptation = c.wantsExposureAdaptation
        }
        camera.vignettingIntensity = 0
        camera.zNear = 0.1
        camera.zFar = 100
        cameraNode.camera = camera
        cameraNode.position = stage.cameraNode.position
        scene.rootNode.addChildNode(cameraNode)

        sceneView.scene = scene
        sceneView.pointOfView = cameraNode
        sceneView.delegate = self
        sceneView.isPlaying = true
        sceneView.rendersContinuously = true
        sceneView.preferredFramesPerSecond = 60
        sceneView.backgroundColor = .black
        sceneView.isUserInteractionEnabled = false
        addSubview(sceneView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        sceneView.frame = bounds
        guard let stage, bounds.height > 0, stageHeight > 0 else { return }
        // focal length in points, shared with the stage camera
        let stageHalf = Double(stage.fieldOfView) * .pi / 360
        let focal = Double(stageHeight) / 2 / tan(stageHalf)
        let skyHalf = atan(Double(bounds.height) / 2 / focal)
        cameraNode.camera?.fieldOfView = CGFloat(skyHalf * 360 / .pi)
        // tilt up so the bottom edge looks exactly where the stage's top edge does
        cameraNode.eulerAngles = SCNVector3(Float(stageHalf + skyHalf), 0, 0)
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if let stage { scene.background.contentsTransform = stage.panoramaTurn() }
    }
}
