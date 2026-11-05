import SwiftUI
import AVFoundation

/// Opening: the visionOS opening film (with alpha) plays over a smoky room, then the
/// logo settles upward and the language question appears as glass pills. (The base and
/// the screen both work for squeezing, so there is nothing else to ask.)
struct OpeningView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.screenMargins) private var m
    @Environment(\.crease) private var crease
    @State private var player = OpeningView.makePlayer()
    @State private var step: Step = .film
    @State private var endObserver: NSObjectProtocol?

    private enum Step { case film, language }

    var body: some View {
        GeometryReader { geo in
            // on the iPhone Duo held upright the film plays above the fold and the question sits below it
            let filmArea = crease?.top.size ?? geo.size
            let filmWidth = min(filmArea.width * (crease == nil ? 0.86 : 0.96), filmArea.height * 2.36 * 0.86)
            let filmY = crease.map { $0.top.midY + 10 } ?? geo.size.height / 2
            let choicesY = crease.map { $0.bottom.minY + $0.bottom.height * 0.35 } ?? geo.size.height * 0.64
            ZStack {
                MoodBackdrop()
                TwinkleField(count: 24, color: Color(hex: 0xFFE6F3))

                TransparentVideoView(player: player)
                    .frame(width: filmWidth, height: filmWidth / 2.36)
                    // The film has its own alpha; only feather the outermost edge a little so
                    // Moodi's head (which flies close to the top) is never faded away.
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03),
                                               .init(color: .black, location: 0.97), .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                            .mask {
                                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.02),
                                                       .init(color: .black, location: 0.98), .init(color: .clear, location: 1)],
                                               startPoint: .top, endPoint: .bottom)
                            }
                    }
                    .scaleEffect(step == .film || crease != nil ? 1 : 0.62)
                    .position(x: geo.size.width / 2, y: filmY)
                    .offset(y: step == .film || crease != nil ? 0 : -geo.size.height * 0.24)
                    .allowsHitTesting(false)

                if step != .film {
                    choices
                        .position(x: geo.size.width / 2, y: choicesY)
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
                    .padding(m.insets)
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
                HStack(spacing: 6) {
                    OpeningPill(title: "中文", highlighted: app.language == .zh) { choose(.zh) }
                    OpeningPill(title: "English", highlighted: app.language == .en) { choose(.en) }
                }
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
        // The question only on the first launch; it can be changed in Settings later.
        if app.onboarded {
            AudioDirector.shared.sfx("sfx_portal", volume: 0.5)
            app.goHome()
            return
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { step = .language }
    }

    private func choose(_ language: Language) {
        app.language = language
        app.onboarded = true
        AudioDirector.shared.sfx("sfx_portal", volume: 0.5)
        app.goHome()
    }
}
