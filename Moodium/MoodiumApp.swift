import SwiftUI
import CoreMotion
import AVKit
import SceneKit

@main struct MoodiumApp: App { var body: some Scene { WindowGroup { Home() } } }

final class Motion: ObservableObject {
    let manager = CMMotionManager()
    @Published var strength = 0.0
    var onPulse: (() -> Void)?
    var last = Date.distantPast
    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // Landscape screen horizontal rocking rotates around device X.
            let speed = abs(motion.rotationRate.x)
            self.strength = min(1, speed / 3)
            if speed > 0.8 && Date().timeIntervalSince(self.last) > 0.35 {
                self.last = Date(); self.onPulse?()
            }
        }
    }
    func stop() { manager.stopDeviceMotionUpdates(); strength = 0 }
}

struct Home: View {
    @Environment(\.scenePhase) private var phase
    @StateObject private var motion = Motion()
    @State private var stage = 0
    @State private var nature = false
    @State private var energy = 0.0
    @State private var selectedWorld: Int? = 0
    @StateObject private var world = SoftWorld()
    @State private var player = AVPlayer(url: Bundle.main.url(forResource: "Opening", withExtension: "mp4")!)
    private var tint: Color { nature ? .mint : .pink }
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(red: 0.08, green: 0.09, blue: 0.19), nature ? Color(red: 0.08, green: 0.28, blue: 0.25) : Color(red: 0.30, green: 0.13, blue: 0.34)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                if stage == 0 {
                    VStack(spacing: 24) {
                        Text("MOODIUM").font(.system(size: 34, weight: .light, design: .rounded)).tracking(8)
                        TransparentVideoView(player: player).frame(height: geo.size.height * 0.55)
                        Text("把一点柔软，带回日常").foregroundStyle(.white.opacity(0.65))
                        Button("进入我的小世界  →") { player.pause(); withAnimation { stage = 1 } }.buttonStyle(.borderedProminent).tint(.purple)
                    }.padding(24).onAppear { player.play() }
                } else if stage == 1 {
                    VStack(spacing: 12) {
                        Text("今天，想去哪里？").font(.largeTitle.bold())
                        GeometryReader { carousel in
                            ScrollView(.horizontal) {
                                HStack(spacing: 18) {
                                    ForEach(0..<2) { index in
                                        WorldModelView(name: index == 0 ? "CandyWorldUI" : "NatureWorldUI")
                                            .frame(width: carousel.size.width * 0.88, height: carousel.size.height)
                                            .allowsHitTesting(false)
                                            .id(index)
                                    }
                                }.scrollTargetLayout()
                            }
                            .contentMargins(.horizontal, carousel.size.width * 0.06, for: .scrollContent)
                            .scrollTargetBehavior(.viewAligned)
                            .scrollPosition(id: $selectedWorld)
                            .scrollIndicators(.hidden)
                        }
                        HStack(spacing: 8) {
                            ForEach(0..<2) { index in
                                Capsule().fill(.white.opacity((selectedWorld ?? 0) == index ? 1 : 0.25))
                                    .frame(width: (selectedWorld ?? 0) == index ? 22 : 7, height: 7)
                            }
                        }
                        Button {
                            let green = selectedWorld == 1
                            nature = green; world.configure(nature: green); energy = 0
                            withAnimation(.spring()) { stage = 2 }; motion.start()
                        } label: {
                            Text(selectedWorld == 1 ? "进入自然世界  →" : "进入糖果世界  →")
                                .font(.title3.bold()).padding(.horizontal, 36).padding(.vertical, 10)
                        }.buttonStyle(.borderedProminent).tint(selectedWorld == 1 ? .mint : .pink)
                        Text("左右滑动选择世界 · 横向放置设备，轻压底座两侧")
                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                    }.padding(.vertical, 18)
                } else {
                    SoftSceneView(world: world).ignoresSafeArea()
                    VStack(spacing: 12) {
                        HStack {
                            Button { motion.stop(); world.clear(); stage = 1 } label: { Image(systemName: "arrow.left") }
                            Text(nature ? "自然世界" : "糖果世界").font(.headline)
                            Spacer()
                            Text(energy >= 1 ? "Moodi，自由啦！" : "左右轻压，让柔软绽放").font(.subheadline)
                            Spacer()
                            Button("重来") { energy = 0; world.clear() }
                        }.padding(14).background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                        HStack(spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("柔软能量  \(Int(energy * 100))%").font(.caption)
                                ProgressView(value: energy).tint(tint)
                            }.frame(maxWidth: 220)
                            Spacer()
                            Label(motion.manager.isDeviceMotionAvailable ? "左右轻压底座" : "此设备不支持运动感应", systemImage: "gyroscope")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        }.padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    }.padding(22)

                }
            }.foregroundStyle(.white)
            .onAppear { world.resize(geo.size); motion.onPulse = { pulse() } }
            .onChange(of: geo.size) { _, size in world.resize(size) }
            .onChange(of: phase) { _, next in if next == .active && stage == 2 { motion.start() } else { motion.stop() } }
        }
    }
    func pulse() { energy = min(1, energy + 0.025); world.burst(); UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
}

struct WorldModelView: UIViewRepresentable {
    let name: String
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X
        let scene = SCNScene()
        if let url = Bundle.main.url(forResource: name, withExtension: "usdz"),
           let source = try? SCNScene(url: url, options: nil) {
            let model = SCNNode()
            for child in source.rootNode.childNodes { model.addChildNode(child) }
            let (lo, hi) = model.boundingBox
            let extent = max(hi.x-lo.x, max(hi.y-lo.y, hi.z-lo.z))
            let scale = extent > 0 ? 3 / extent : 1
            model.scale = SCNVector3(scale, scale, scale)
            model.position = SCNVector3(-(lo.x+hi.x)*scale/2, -(lo.y+hi.y)*scale/2, -(lo.z+hi.z)*scale/2)
            // FBX display boards lie on the XZ plane; stand them up toward the camera.
            let facing = SCNNode()
            facing.eulerAngles.x = .pi / 2
            facing.addChildNode(model)
            scene.rootNode.addChildNode(facing)
        }
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.position = SCNVector3(0, 0, 4.0)
        camera.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(camera)
        view.scene = scene; view.pointOfView = camera
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {}
}
