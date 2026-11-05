import SwiftUI
import SceneKit
import SpriteKit

/// The squeeze screen: the 3D stage and 2D effects full-screen, the energy ring above the
/// pillow, Moodi's subtitles, and glass controls in the corners.
struct SqueezeView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.screenMargins) private var m
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var director: SqueezeDirector
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var showBagGuide = false
    @Environment(\.hinge) private var hinge
    @Environment(\.crease) private var crease
    @StateObject private var fireworks = FireworksShow()
    @State private var currentFold: TabletopFold?

    let world: MoodWorld

    init(world: MoodWorld) {
        self.world = world
        _director = StateObject(wrappedValue: SqueezeDirector(world: world))
    }

    var body: some View {
        GeometryReader { geo in
            // When the iPhone Duo's fold crosses the screen (held upright, flat or half folded) the
            // stage and controls take the bottom half and the top half becomes a fireworks sky;
            // everywhere else both rects are the screen.
            let fold = TabletopFold.detect(crease: crease, hinge: hinge)
            let full = CGRect(origin: .zero, size: geo.size)
            let stageRect = fold?.bottom ?? full
            let canvasRect = fold?.stage ?? full
            let skyRect = fold?.top ?? full
            // the energy ring floats above the pillow (on the bottom half when folded, so the sky stays clear)
            let ringCenter = CGPoint(x: stageRect.midX, y: stageRect.minY + stageRect.height * (fold == nil ? 0.19 : 0.17))
            let ringSize = fold == nil ? full.size : CGSize(width: stageRect.width, height: stageRect.height * 0.8)
            ZStack {
                SqueezeCanvas(director: director)
                    .gesture(touchGesture(width: canvasRect.width))
                    .simultaneousGesture(SpatialTapGesture(coordinateSpace: .local).onEnded { director.tap(at: $0.location) })
                    .frame(width: canvasRect.width, height: canvasRect.height)
                    .position(x: canvasRect.midX, y: canvasRect.midY)

                // the sky above the fold, fading into the stage's own sky across it
                if let fold { TabletopSky(world: world, fold: fold) }

                ModeAtmosphere(director: director, world: world)
                    .frame(width: canvasRect.width, height: canvasRect.height)
                    .position(x: canvasRect.midX, y: canvasRect.midY)

                if fold != nil { FireworksLayer(show: fireworks) }

                ZStack {
                    if director.phase != .complete {
                        switch director.mode {
                        case .rhythm: RhythmGuide(director: director, accent: world.accent).transition(.opacity)
                        case .breath: BreathGuide(director: director, accent: world.accent).transition(.opacity)
                        case .free: EmptyView()
                        }
                    }
                    EnergyRing(energy: director.energy, accent: world.accent, lastSqueeze: director.lastSqueeze)
                        .opacity(director.phase == .intro && director.energy == 0 ? 0.55 : 1)
                        .animation(.easeOut(duration: 0.5), value: director.phase)
                }
                .animation(.easeInOut(duration: 0.35), value: director.mode)
                .scaleEffect(ringScale(ringSize))
                .position(ringCenter)

                toasts(ringCenter, scale: ringScale(ringSize))

                // controls: top corners of the stage (just under the fold when folded)
                pinned(stageRect, .top, EdgeInsets(top: fold == nil ? m.top : 10, leading: m.leading, bottom: 0, trailing: m.trailing)) {
                    hudButtons
                }

                // Moodi's lines and the guide: bottom of the screen, or just above the fold
                pinned(fold == nil ? full : skyRect, .bottom,
                       EdgeInsets(top: 0, leading: m.leading, bottom: fold == nil ? m.bottom : Crease.gap + 6, trailing: m.trailing)) {
                    captions
                }

                pinned(stageRect, .trailing, EdgeInsets(top: fold == nil ? 0 : 56, leading: 0, bottom: fold == nil ? 12 : m.bottom, trailing: m.trailing)) {
                    ModeBar(director: director, showHelp: $showHelp)
                        .opacity(director.phase == .complete ? 0 : 1)
                        .animation(.easeOut(duration: 0.3), value: director.phase)
                        .disabled(director.phase == .complete)
                }

                if director.showCard {
                    pinned(stageRect, .center, EdgeInsets()) { completionCard }
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }

                if showHelp {
                    ModeHelpCard(world: world, isPresented: $showHelp) { openBagGuide() }.transition(.opacity)
                }
                if showBagGuide {
                    BagGuide(world: world, probe: director.probe) { closeBagGuide() }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                if showSettings { SettingsPanel(isPresented: $showSettings).transition(.opacity) }
            }
            .foregroundStyle(.white)
            .onAppear { currentFold = fold }
            .onChange(of: fold) { _, f in currentFold = f }
        }
        .ignoresSafeArea()
        .onAppear {
            configureDirector()
            fireworks.configure(world: world)
            // the first time in any world, show how to use the bag before Moodi falls in
            if !app.bagGuided { showBagGuide = true; director.beginGuide() }
            director.start()
            #if MOODIUM_AUTOPILOT
            if ProcessInfo.processInfo.environment["HELP"] != nil { showHelp = true }
            #endif
        }
        .onReceive(director.skyCues) { cue in launchFireworks(cue) }
        .onDisappear { director.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { director.resume() } else { director.pause() }
        }
        .onChange(of: app.language) { _, _ in configureDirector() }
        .onChange(of: app.sensitivity) { _, _ in configureDirector() }
    }

    private func configureDirector() {
        director.configure(language: app.language, sensitivity: app.sensitivity, mood: app.preSample?.mood)
    }

    private func openBagGuide() {
        director.beginGuide()
        withAnimation(.easeOut(duration: 0.3)) { showBagGuide = true }
    }

    private func closeBagGuide() {
        app.bagGuided = true
        withAnimation(.easeOut(duration: 0.3)) { showBagGuide = false }
        director.endGuide()
    }

    private func wish() {
        app.openWish(world, after: director.metrics)
    }

    private func exit() {
        app.leaveWorld(director.metrics)
    }

    /// Mode switch, gift and "energy full" messages under the ring.
    private func toasts(_ ring: CGPoint, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if director.modeToastAt != nil {
                HStack(spacing: 6) {
                    Image(asset: director.mode.icon).resizable().frame(width: 16, height: 16)
                    Text(director.mode.toast(app.language)).font(.moodium(14, .bold))
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                .glass(tint: world.accent, amount: 0.3)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .frame(width: 220)
        .position(x: ring.x + 100 * scale + 120, y: ring.y)
        .allowsHitTesting(false)
    }

    private func ringScale(_ size: CGSize) -> CGFloat {
        min(1.1, max(0.62, size.height / 520))
    }

    // MARK: HUD

    private var hudButtons: some View {
        HStack(spacing: 10) {
            GlassIconButton(symbol: "chevron.left") { exit() }
            Spacer()
            GlassIconButton(symbol: app.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") { app.muted.toggle() }
            GlassIconButton(symbol: "gearshape.fill") { withAnimation { showSettings = true } }
        }
    }

    /// Places `content` inside `rect` with the given alignment and insets.
    private func pinned<V: View>(_ rect: CGRect, _ alignment: Alignment, _ insets: EdgeInsets, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(insets)
            .frame(width: rect.width, height: rect.height, alignment: alignment)
            .position(x: rect.midX, y: rect.midY)
    }

    /// Sends a fireworks rocket up from the stage into the sky for each squeeze, gift and the finale.
    private func launchFireworks(_ cue: SqueezeDirector.SkyCue) {
        guard let fold = currentFold else { return }
        let stage = fold.stage
        func origin(_ p: CGPoint?) -> CGPoint {
            guard let p else { return CGPoint(x: stage.midX, y: stage.minY + stage.height * 0.4) }
            return CGPoint(x: stage.minX + p.x, y: stage.minY + p.y)
        }
        switch cue {
        case .squeeze(let intensity, let from):
            fireworks.launch(from: origin(from), sky: fold.top, reach: fold.reach, power: 0.45 + 0.55 * intensity,
                             shape: intensity > 0.75 ? .ring : .sphere)
        case .gift(let from):
            for k in 0..<3 {
                fireworks.launch(from: origin(from), sky: fold.top, reach: fold.reach, power: 1,
                                 shape: k == 1 ? .double : .sphere, delay: Double(k) * 0.18)
            }
            AudioDirector.shared.sfx("sfx_chime", volume: 0.3)
        case .finale(let from):
            let shapes: [FireworksShow.Shape] = world == .candy
                ? [.heart, .sphere, .double, .heart, .ring, .sphere, .heart, .double, .sphere]
                : [.double, .sphere, .ring, .double, .sphere, .ring, .double, .sphere, .sphere]
            for (k, shape) in shapes.enumerated() {
                fireworks.launch(from: origin(from), sky: fold.top, reach: fold.reach, power: 1.15,
                                 shape: shape, delay: Double(k) * 0.28)
            }
        }
    }

    private var captions: some View {
            VStack(spacing: 8) {
                if let subtitle = director.subtitle, !director.showCard {
                    HStack(spacing: 8) {
                        Image(asset: "moodi_happy").resizable().frame(width: 24, height: 24)
                        Text(subtitle).font(.moodium(16, .semibold))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .glass(tint: Palette.lavender, amount: 0.2)
                    // just above the fold it only fades, so it never slides across it
                    .transition(crease == nil ? .opacity.combined(with: .move(edge: .bottom)) : .opacity)
                    .id(subtitle)
                }
                if let guide = director.guide, director.subtitle == nil {
                    Text(guide)
                        .font(.moodium(14, .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .glass(shadow: false)
                        .transition(.opacity)
                        .id(guide)
                } else if director.showHint {
                    Label(hintText, systemImage: "hand.tap.fill")
                        .font(.moodium(14, .medium))
                        .foregroundStyle(Palette.textMuted)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .glass(shadow: false)
                        .phaseAnimator([1.0, 0.6]) { v, a in v.opacity(a) } animation: { _ in .easeInOut(duration: 1.2) }
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: 360)
            .padding(.bottom, 4)
    }

    private var hintText: String {
        app.t("按压感官袋或屏幕，把 Moodi 挤出来", "Press the bag or the screen to squeeze Moodi out")
    }

    /// After Moodi is out: a small card in the middle of the screen with two choices.
    private var completionCard: some View {
        VStack(spacing: 12) {
            VStack(spacing: 3) {
                Text(app.t("Moodi 出来了", "Moodi is free")).font(.moodium(19, .bold))
                Text(director.giftsGrown == 4
                     ? app.t("4 件礼物全部收齐", "All 4 gifts collected")
                     : app.t("谢谢你温柔的按压", "Thanks for every gentle squeeze"))
                    .font(.moodium(13)).foregroundStyle(Palette.textMuted)
            }
            HStack(spacing: 10) {
                Button { wish() } label: {
                    Label(app.t("许个心愿", "Make a wish"), systemImage: "wind").lineLimit(1).fixedSize()
                }
                .buttonStyle(GlassButtonStyle(tint: world.accent, prominent: true, compact: true))
                Button { director.replay() } label: {
                    Label(app.t("再捏一次", "Squeeze again"), systemImage: "arrow.counterclockwise").lineLimit(1).fixedSize()
                }
                .buttonStyle(GlassButtonStyle(compact: true))
            }
            // nothing more to do: just stay with Moodi in the world for a while
            Button { director.dismissCard() } label: {
                Text(app.t("先在这里待一会儿", "Just stay here a while"))
                    .font(.moodium(13, .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .underline(color: .white.opacity(0.35))
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Panel.padding).padding(.top, Panel.padding).padding(.bottom, Panel.padding - 6)
        .glass(Panel.shape, tint: Palette.smoke, amount: 0.55)
        // in the middle of the screen
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
