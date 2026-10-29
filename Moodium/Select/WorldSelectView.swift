import SwiftUI

/// Level select: blurred world panorama behind a 3D carousel of the two world islands,
/// Moodi peeking beside the selected one, and the glass slide-to-enter control.
struct WorldSelectView: View {
    @EnvironmentObject private var app: AppModel
    @StateObject private var stage = CarouselStage()
    @State private var showSettings = false
    @State private var dragging = false
    @State private var entering = false

    private var world: MoodWorld { .at(stage.selection) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backdrop(size: geo.size)

                CarouselView(stage: stage)
                    .ignoresSafeArea()
                    .gesture(carouselDrag(width: geo.size.width))

                placeholders(size: geo.size)

                MoodiPeek(world: world, line: world.moodiLine(app.language), visible: !dragging && !entering)
                    .position(x: geo.size.width * 0.5 + min(geo.size.width * 0.17, 190), y: geo.size.height * 0.27)

                overlay(size: geo.size)

                if showSettings {
                    SettingsPanel(isPresented: $showSettings).transition(.opacity)
                }
            }
            .foregroundStyle(.white)
        }
        .onAppear {
            stage.resetEnter()
            stage.select(app.lastWorld.index)
            entering = false
        }
    }

    // MARK: Pieces

    /// Blurred panorama of the selected world, pinned to the screen size so it never widens the layout.
    private func backdrop(size: CGSize) -> some View {
        // Color.clear takes the screen size; the overlay can't grow past it.
        Color.clear.overlay {
          ZStack {
            Palette.ink
            ForEach(MoodWorld.allCases) { w in
                if let image = Res.image(w.backdrop) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 22)
                        .scaleEffect(1.15)
                        .opacity(w == world ? 1 : 0)
                }
            }
            LinearGradient(colors: [Palette.ink.opacity(0.72), Palette.ink.opacity(0.42), Palette.ink.opacity(0.9)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [world.accent.opacity(0.22), .clear], center: .center, startRadius: 10, endRadius: 420)
          }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.6), value: world)
        .ignoresSafeArea()
    }

    /// While a world's model is still loading, show its icon glowing in place.
    private func placeholders(size: CGSize) -> some View {
        ForEach(MoodWorld.allCases) { w in
            if !stage.loaded[w.index] {
                let offset = CGFloat(w.index - stage.selection)
                Image(asset: w.icon)
                    .resizable().scaledToFit()
                    .frame(width: 130)
                    .opacity(offset == 0 ? 0.9 : 0.4)
                    .scaleEffect(offset == 0 ? 1 : 0.7)
                    .shadow(color: w.accent.opacity(0.6), radius: 24)
                    .position(x: size.width / 2 + offset * size.width * 0.4, y: size.height * 0.44)
                    .phaseAnimator([0.92, 1.0]) { view, s in view.scaleEffect(s) } animation: { _ in .easeInOut(duration: 1.1) }
                    .allowsHitTesting(false)
            }
        }
    }

    private func overlay(size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.t("今天，想去哪里？", "Where to today?"))
                        .font(.moodium(28, .bold))
                    Text(app.t("左右滑动，挑一个想去的小世界", "Swipe to pick a little world"))
                        .font(.moodium(14)).foregroundStyle(Palette.textMuted)
                }
                Spacer()
                GlassIconButton(symbol: "gearshape.fill") { withAnimation { showSettings = true } }
            }
            .padding(.top, 14)

            Spacer()

            HStack {
                GlassIconButton(symbol: "chevron.left", size: 44) { stage.select(0) }
                    .opacity(stage.selection > 0 ? 1 : 0).disabled(stage.selection == 0)
                Spacer()
                GlassIconButton(symbol: "chevron.right", size: 44) { stage.select(1) }
                    .opacity(stage.selection < 1 ? 1 : 0).disabled(stage.selection == 1)
            }
            .animation(.easeOut(duration: 0.2), value: stage.selection)

            Spacer()

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(asset: world.icon).resizable().scaledToFit().frame(width: 26, height: 26)
                    Text(world.name(app.language)).font(.moodium(20, .bold))
                    Text("·").foregroundStyle(Palette.textMuted)
                    Text(world.tagline(app.language)).font(.moodium(15)).foregroundStyle(Palette.textMuted)
                }
                .id(world)
                .transition(.opacity)

                GlassSlideToEnter(world: world, label: world.enterLabel(app.language),
                                  busyLabel: app.t("正在进入…", "Entering…")) { enter() }
                    .id("\(world.rawValue)-\(app.language.rawValue)")

                HStack(spacing: 7) {
                    ForEach(0..<2, id: \.self) { i in
                        Capsule().fill(.white.opacity(stage.selection == i ? 1 : 0.3))
                            .frame(width: stage.selection == i ? 20 : 7, height: 7)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: stage.selection)
            }
            .animation(.easeInOut(duration: 0.3), value: world)
            .padding(.bottom, 10)
            .opacity(dragging ? 0.35 : 1)
            .animation(.easeOut(duration: 0.2), value: dragging)
        }
        .padding(.horizontal, 22)
    }

    private func carouselDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !entering else { return }
                dragging = true
                stage.dragChanged(Float(value.translation.width / (width * 0.42)))
            }
            .onEnded { value in
                guard !entering else { return }
                dragging = false
                stage.dragEnded(Float(value.translation.width / (width * 0.42)),
                                predicted: Float(value.predictedEndTranslation.width / (width * 0.42)))
            }
    }

    private func enter() {
        entering = true
        stage.playEnter(stage.selection)
        AudioDirector.shared.sfx("sfx_portal", volume: 0.6)
        let chosen = world
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { app.enter(chosen) }
    }
}

/// Moodi peeking out beside the selected island, breathing and saying a line.
private struct MoodiPeek: View {
    let world: MoodWorld
    let line: String
    let visible: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let bob = sin(t * 2.0) * 5
            let breathe = 1 + 0.03 * sin(t * 2.0 + 0.6)
            VStack(spacing: 4) {
                Text(line)
                    .font(.moodium(13, .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .glass(RoundedRectangle(cornerRadius: 14, style: .continuous), tint: world.accent, amount: 0.25)
                    .fixedSize()
                Image(asset: world == .candy ? "moodi_happy" : "moodi_calm")
                    .resizable().scaledToFit()
                    .frame(width: 74, height: 74)
                    .scaleEffect(x: breathe, y: 2 - breathe)
                    .shadow(color: Palette.lavender.opacity(0.6), radius: 14)
                    .offset(y: bob)
            }
        }
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.85)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: visible)
        .id(world)
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}
