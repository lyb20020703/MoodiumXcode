import SwiftUI
import SpriteKit
import CoreMotion
import AVKit

@main struct MoodiumApp: App { var body: some Scene { WindowGroup { Home() } } }

final class Motion: ObservableObject {
    let manager = CMMotionManager()
    @Published var strength = 0.0
    var baseline = 0.0
    var onPulse: (() -> Void)?
    var last = Date.distantPast
    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let speed = abs(motion.rotationRate.x) + abs(motion.rotationRate.y)
            self.strength = min(1, speed / 3)
            if speed > 0.8 && Date().timeIntervalSince(self.last) > 0.35 {
                self.last = Date(); self.onPulse?()
            }
        }
    }
    func stop() { manager.stopDeviceMotionUpdates(); strength = 0 }
}

final class ParticleWorld: SKScene {
    var nature = false
    override func didMove(to view: SKView) { backgroundColor = .clear; physicsWorld.gravity = CGVector(dx: 0, dy: -1.5); wall() }
    override func didChangeSize(_ oldSize: CGSize) { wall() }
    func wall() { guard size.width > 0, size.height > 0 else { return }; physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(origin: .zero, size: size)) }
    func burst() {
        guard size.width > 0 else { return }
        for _ in 0..<18 {
            let node = SKShapeNode(ellipseOf: CGSize(width: nature ? 12 : 9, height: nature ? 6 : 9))
            node.fillColor = nature ? [.systemMint, .systemGreen, .yellow].randomElement()! : [.systemPink, .cyan, .yellow, .white].randomElement()!
            node.strokeColor = .clear
            node.position = CGPoint(x: size.width / 2, y: size.height * 0.46)
            node.physicsBody = SKPhysicsBody(circleOfRadius: 6)
            node.physicsBody?.restitution = 0.85
            node.physicsBody?.linearDamping = 0.15
            addChild(node)
            node.physicsBody?.velocity = CGVector(dx: Double.random(in: -230...230), dy: Double.random(in: 120...380))
            node.run(.sequence([.wait(forDuration: 4), .fadeOut(withDuration: 1), .removeFromParent()]))
        }
    }
}

struct Home: View {
    @Environment(\.scenePhase) private var phase
    @StateObject private var motion = Motion()
    @State private var stage = 0
    @State private var nature = false
    @State private var energy = 0.0
    @State private var sensitivity = 1.0
    @State private var world = ParticleWorld()
    @State private var player = AVPlayer(url: Bundle.main.url(forResource: "Opening", withExtension: "mp4")!)
    private var tint: Color { nature ? .mint : .pink }
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(red: 0.08, green: 0.09, blue: 0.19), nature ? Color(red: 0.08, green: 0.28, blue: 0.25) : Color(red: 0.30, green: 0.13, blue: 0.34)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                if stage == 0 {
                    VStack(spacing: 24) {
                        Text("MOODIUM").font(.system(size: 34, weight: .light, design: .rounded)).tracking(8)
                        VideoPlayer(player: player).frame(height: geo.size.height * 0.55).clipShape(RoundedRectangle(cornerRadius: 32))
                        Text("把一点柔软，带回日常").foregroundStyle(.white.opacity(0.65))
                        Button("进入我的小世界  →") { player.pause(); withAnimation { stage = 1 } }.buttonStyle(.borderedProminent).tint(.purple)
                    }.padding(24).onAppear { player.play() }
                } else if stage == 1 {
                    VStack(alignment: .leading, spacing: 26) {
                        Text("MOODIUM / POCKET").font(.caption).tracking(4).foregroundStyle(.white.opacity(0.5))
                        Text("今天，想去哪里？").font(.largeTitle.bold())
                        Text("让每一次轻轻按压，都长出一点好心情。") .foregroundStyle(.white.opacity(0.6))
                        card("糖果星球", subtitle: "轻快 · 弹跳 · 释放", symbol: "sparkles", green: false)
                        card("呼吸森林", subtitle: "舒缓 · 生长 · 陪伴", symbol: "leaf.fill", green: true)
                        Text("将手机稳固吸附在感官底座中央，再轻压底座两侧。").font(.footnote).foregroundStyle(.white.opacity(0.5))
                    }.padding(28)
                } else {
                    SpriteView(scene: world, options: [.allowsTransparency]).ignoresSafeArea().allowsHitTesting(false)
                    VStack(spacing: 20) {
                        HStack { Button { motion.stop(); stage = 1 } label: { Image(systemName: "arrow.left") }; Spacer(); Text(nature ? "呼吸森林" : "糖果星球"); Spacer(); Button("重来") { energy = 0 } }.foregroundStyle(.white.opacity(0.8))
                        HStack { Circle().fill(motion.manager.isDeviceMotionAvailable ? .green : .orange).frame(width: 6, height: 6); Text(motion.manager.isDeviceMotionAvailable ? "感官底座 · 运动感应中" : "触摸演示模式").font(.caption) }
                        Spacer()
                        Image(uiImage: UIImage(named: "Moodi.png") ?? UIImage()).resizable().scaledToFit().frame(width: 160, height: 160).scaleEffect(1 + motion.strength * 0.12).offset(y: energy >= 1 ? -35 : 0).animation(.spring(), value: energy)
                            .background { RoundedRectangle(cornerRadius: 70).fill(tint.opacity(0.16)).frame(width: 220, height: 200).scaleEffect(x: 1 + motion.strength * 0.15, y: 1 - motion.strength * 0.1) }
                        Text(energy >= 1 ? "Moodi，自由啦！" : "轻轻按压，唤醒 Moodi").font(.title2.bold())
                        Text(energy >= 1 ? "继续按压，让小世界盛放" : "左右交替按压底座，让手机轻轻摇摆").font(.footnote).foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        HStack { Text("柔软能量"); Spacer(); Text("\(Int(energy * 100))%") }.font(.caption)
                        ProgressView(value: energy).tint(tint)
                        HStack { Text("灵敏度").font(.caption); Slider(value: $sensitivity, in: 0.5...2).tint(tint) }
                        Button("轻触体验一次按压") { pulse() }.buttonStyle(.borderedProminent).tint(tint.opacity(0.6))
                        Text("运动感应无法测量真实压力 · 无需用力摇晃").font(.caption2).foregroundStyle(.white.opacity(0.4))
                    }.padding(28)
                }
            }.foregroundStyle(.white)
            .onAppear { world.size = geo.size; world.scaleMode = .resizeFill; motion.onPulse = { pulse() } }
            .onChange(of: phase) { _, next in if next == .active && stage == 2 { motion.start() } else { motion.stop() } }
        }
    }
    func pulse() { energy = min(1, energy + 0.025 * sensitivity); world.burst(); UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    func card(_ title: String, subtitle: String, symbol: String, green: Bool) -> some View {
        Button { nature = green; world.nature = green; energy = 0; withAnimation(.spring()) { stage = 2 }; motion.start() } label: {
            HStack(spacing: 20) { Image(systemName: symbol).font(.system(size: 36)); VStack(alignment: .leading, spacing: 10) { Text(title).font(.title2.bold()); Text(subtitle).font(.caption).opacity(0.65) }; Spacer(); Image(systemName: "arrow.up.right") }.padding(28).frame(maxWidth: .infinity, minHeight: 145).background((green ? Color.mint : Color.pink).opacity(0.18), in: RoundedRectangle(cornerRadius: 30)).overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.12)))
        }.buttonStyle(.plain)
    }
}
