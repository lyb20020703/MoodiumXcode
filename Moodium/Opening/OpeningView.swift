import SwiftUI
import AVFoundation

/// Opening: the visionOS opening film (with alpha) plays over a smoky room, then the
/// logo settles upward and the same two questions as visionOS appear as glass pills:
/// language, then whether the user has the sensory base.
struct OpeningView: View {
    @EnvironmentObject private var app: AppModel
    @State private var player = OpeningView.makePlayer()
    @State private var step: Step = .film
    @State private var endObserver: NSObjectProtocol?

    private enum Step { case film, language, base }

    var body: some View {
        GeometryReader { geo in
            let filmWidth = min(geo.size.width * 0.86, geo.size.height * 2.36 * 0.86)
            ZStack {
                MoodBackdrop()
                TwinkleField(count: 24, color: Color(hex: 0xFFE6F3))

                TransparentVideoView(player: player)
                    .frame(width: filmWidth, height: filmWidth / 2.36)
                    // Feather the film's edges so its frame never shows against the room.
                    .mask {
                        RadialGradient(colors: [.black, .black, .clear], center: .center,
                                       startRadius: 0, endRadius: filmWidth * 0.5)
                            .scaleEffect(x: 1, y: 0.62)
                    }
                    .scaleEffect(step == .film ? 1 : 0.62)
                    .offset(y: step == .film ? 0 : -geo.size.height * 0.24)
                    .allowsHitTesting(false)

                if step != .film {
                    choices
                        .offset(y: geo.size.height * 0.14)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if step == .film {
                    VStack {
                        HStack {
                            Spacer()
                            Button { finishFilm() } label: {
                                Label(app.t("跳过", "Skip"), systemImage: "forward.fill")
                                    .labelStyle(.titleAndIcon)
                                    .font(.moodium(14, .semibold))
                            }
                            .buttonStyle(GlassButtonStyle())
                        }
                        Spacer()
                    }
                    .padding(20)
                    .transition(.opacity)
                }
            }
            .foregroundStyle(.white)
        }
        .onAppear(perform: startFilm)
        .onDisappear {
            player.pause()
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        }
    }

    @ViewBuilder private var choices: some View {
        VStack(spacing: 10) {
            switch step {
            case .language:
                Text("选择语言 · Choose language")
                    .font(.moodium(17, .medium)).foregroundStyle(Palette.textMuted)
                HStack(spacing: 6) {
                    OpeningPill(title: "中文", highlighted: app.language == .zh) { choose(.zh) }
                    OpeningPill(title: "English", highlighted: app.language == .en) { choose(.en) }
                }
            case .base:
                Text(app.t("你有 Moodium 感官底座吗？", "Do you have the Moodium sensory base?"))
                    .font(.moodium(17, .medium)).foregroundStyle(Palette.textMuted)
                HStack(spacing: 6) {
                    OpeningPill(title: app.t("有", "Yes"), highlighted: app.hasBase) { chooseBase(true) }
                    OpeningPill(title: app.t("没有", "No"), highlighted: !app.hasBase) { chooseBase(false) }
                }
                Text(app.t("没有也没关系，按住屏幕再松开也能捏捏", "No base? Press and release the screen to squeeze"))
                    .font(.moodium(13)).foregroundStyle(.white.opacity(0.5))
            case .film:
                EmptyView()
            }
        }
        .id(step)
        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.94)), removal: .opacity))
    }

    private static func makePlayer() -> AVPlayer {
        guard let url = Res.url("Opening", "mp4") else { return AVPlayer() }
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        return player
    }

    private func startFilm() {
        player.seek(to: .zero)
        player.play()
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: player.currentItem, queue: .main) { _ in
            finishFilm()
        }
    }

    private func finishFilm() {
        guard step == .film else { return }
        // Hold the final logo frame and let it rise to make room for the questions.
        if let item = player.currentItem, item.duration.isNumeric {
            player.seek(to: item.duration - CMTime(value: 1, timescale: 30), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.pause()
        withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { step = .language }
    }

    private func choose(_ language: Language) {
        app.language = language
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { step = .base }
    }

    private func chooseBase(_ has: Bool) {
        app.hasBase = has
        AudioDirector.shared.sfx("sfx_portal", volume: 0.5)
        app.stage = .select
    }
}
