import SwiftUI
import SceneKit
import SpriteKit

/// The squeeze screen: the 3D stage and 2D effects full-screen, the energy ring above the
/// pillow, Moodi's subtitles, and glass controls in the corners.
struct SqueezeView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var director: SqueezeDirector
    @State private var showSettings = false

    let world: MoodWorld

    init(world: MoodWorld) {
        self.world = world
        _director = StateObject(wrappedValue: SqueezeDirector(world: world))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SqueezeCanvas(director: director)
                    .ignoresSafeArea()
                    .gesture(touchGesture(width: geo.size.width), including: director.touchMode ? .all : .subviews)

                EnergyRing(energy: director.energy, accent: world.accent, lastSqueeze: director.lastSqueeze)
                    .scaleEffect(ringScale(geo.size))
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.19)
                    .opacity(director.phase == .intro && director.energy == 0 ? 0.55 : 1)
                    .animation(.easeOut(duration: 0.5), value: director.phase)

                hud
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)

                if director.showCard { completionCard.transition(.scale(scale: 0.9).combined(with: .opacity)) }

                if showSettings { SettingsPanel(isPresented: $showSettings).transition(.opacity) }
            }
            .foregroundStyle(.white)
        }
        .onAppear {
            configureDirector()
            director.start()
        }
        .onDisappear { director.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { director.resume() } else { director.pause() }
        }
        .onChange(of: app.language) { _, _ in configureDirector() }
        .onChange(of: app.hasBase) { _, _ in configureDirector() }
        .onChange(of: app.sensitivity) { _, _ in configureDirector() }
    }

    private func configureDirector() {
        director.configure(language: app.language, hasBase: app.hasBase, sensitivity: app.sensitivity)
    }

    private func ringScale(_ size: CGSize) -> CGFloat {
        min(1.1, max(0.62, size.height / 520))
    }

    // MARK: HUD

    private var hud: some View {
        VStack {
            HStack(spacing: 10) {
                GlassIconButton(symbol: "chevron.left") { app.backToSelect() }
                HStack(spacing: 6) {
                    Image(asset: world.icon).resizable().scaledToFit().frame(width: 22, height: 22)
                    Text(world.name(app.language)).font(.moodium(15, .semibold))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .glass(tint: world.accent, amount: 0.15)
                Spacer()
                GlassIconButton(symbol: app.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") { app.muted.toggle() }
                GlassIconButton(symbol: "gearshape.fill") { withAnimation { showSettings = true } }
            }
            Spacer()
            VStack(spacing: 8) {
                if let subtitle = director.subtitle {
                    HStack(spacing: 8) {
                        Image(asset: "moodi_happy").resizable().frame(width: 24, height: 24)
                        Text(subtitle).font(.moodium(16, .semibold))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .glass(tint: Palette.lavender, amount: 0.2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .id(subtitle)
                }
                if director.showHint {
                    Label(hintText, systemImage: director.touchMode ? "hand.tap.fill" : "arrow.left.and.right")
                        .font(.moodium(14, .medium))
                        .foregroundStyle(Palette.textMuted)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .glass(shadow: false)
                        .phaseAnimator([1.0, 0.6]) { v, a in v.opacity(a) } animation: { _ in .easeInOut(duration: 1.2) }
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: 520)
        }
    }

    private var hintText: String {
        if director.sensorMissing {
            return app.t("没检测到运动传感器，按住屏幕再松开来捏捏", "No motion sensor found — press and release the screen")
        }
        return director.touchMode
            ? app.t("按住屏幕，再松开，把 Moodi 挤出来", "Press and hold, then let go to squeeze Moodi out")
            : app.t("轻压底座两侧，把 Moodi 挤出来", "Press either side of the base to squeeze Moodi out")
    }

    private var completionCard: some View {
        ZStack {
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .trailing).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(app.t("Moodi 得救啦！", "Moodi is free!")).font(.moodium(26, .bold))
                Text(app.t("谢谢你每一次温柔的按压", "Thank you for every gentle squeeze"))
                    .font(.moodium(15)).foregroundStyle(Palette.textMuted)
                HStack(spacing: 12) {
                    Button { director.replay() } label: {
                        Label(app.t("再救一次", "Again"), systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(GlassButtonStyle(tint: world.accent, prominent: true))
                    Button { app.backToSelect() } label: {
                        Label(app.t("换个世界", "Other world"), systemImage: "globe.asia.australia.fill")
                    }
                    .buttonStyle(GlassButtonStyle())
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 30).padding(.vertical, 24)
            .glass(RoundedRectangle(cornerRadius: 30, style: .continuous), tint: Palette.smoke, amount: 0.55)
            // Sit to the side so Moodi, floating in the middle, stays in view.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 28)
            .offset(y: 30)
        }
    }

    // MARK: Touch fallback

    private func touchGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in director.touchBegan() }
            .onEnded { value in director.touchEnded(atX: value.location.x, width: width) }
    }
}

/// Hosts the SceneKit stage with the SpriteKit effects layered on top.
struct SqueezeCanvas: UIViewRepresentable {
    let director: SqueezeDirector

    func makeUIView(context: Context) -> SqueezeContainer {
        SqueezeContainer(director: director)
    }

    func updateUIView(_ view: SqueezeContainer, context: Context) {}
}

final class SqueezeContainer: UIView {
    private let sceneView: SCNView
    private let effectsView = SKView()
    private weak var director: SqueezeDirector?
    private var lastSize = CGSize.zero

    init(director: SqueezeDirector) {
        self.director = director
        sceneView = SCNView(frame: .zero)
        super.init(frame: .zero)
        backgroundColor = .black

        let stage = director.stage
        sceneView.scene = stage.scene
        sceneView.pointOfView = stage.cameraNode
        sceneView.delegate = stage
        sceneView.isPlaying = true
        sceneView.rendersContinuously = true
        sceneView.antialiasingMode = .multisampling4X
        sceneView.preferredFramesPerSecond = 60
        sceneView.backgroundColor = .black
        stage.view = sceneView
        addSubview(sceneView)

        effectsView.allowsTransparency = true
        effectsView.backgroundColor = .clear
        effectsView.isUserInteractionEnabled = false
        effectsView.ignoresSiblingOrder = true
        effectsView.preferredFramesPerSecond = 60
        effectsView.presentScene(director.sparkles)
        addSubview(effectsView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        sceneView.frame = bounds
        effectsView.frame = bounds
        guard bounds.size != lastSize, bounds.width > 0 else { return }
        lastSize = bounds.size
        director?.stage.resize(bounds.size)
        director?.sparkles.size = bounds.size
        // Projection needs a laid-out view; wait one runloop.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.director?.layoutChanged() }
        }
    }
}
