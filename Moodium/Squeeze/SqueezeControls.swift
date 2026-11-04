import SwiftUI

// MARK: - Mode bar

/// The visionOS tabletop mode pucks (ModeButtonBar): free / rhythm / breath and "how to play".
struct ModeBar: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var director: SqueezeDirector
    @Binding var showHelp: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(SqueezeMode.allCases) { m in
                puck(icon: m.icon, label: m.name(app.language), selected: director.mode == m,
                     recommended: director.recommendedMode == m) {
                    director.requestMode(m)
                }
            }
            puck(icon: "mode_icon_help", label: app.t("玩法", "How to"), selected: false, recommended: false) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showHelp = true }
            }
        }
        .padding(.vertical, 6)
        .glass(RoundedRectangle(cornerRadius: 28, style: .continuous), tint: Palette.ink, amount: 0.32, shadow: false)
    }

    private func puck(icon: String, label: String, selected: Bool, recommended: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                ZStack {
                    if selected {
                        Image(asset: "mode_btn_selected_glow").resizable()
                            .frame(width: 50, height: 50)
                            .colorMultiply(director.world.accent)
                            .transition(.opacity)
                    }
                    Image(asset: "mode_btn_base").resizable().frame(width: 38, height: 38)
                    Image(asset: icon).resizable().frame(width: 19, height: 19)
                        .opacity(selected ? 1 : 0.78)
                    if recommended {
                        Image(asset: "icon_star").resizable().frame(width: 12, height: 12)
                            .padding(3)
                            .background(Circle().fill(director.world.accent))
                            .offset(x: 15, y: -15)
                    }
                }
                .frame(width: 42, height: 42)
                Text(label)
                    .font(.moodium(10, selected ? .bold : .medium))
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.82))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 52)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .animation(.easeOut(duration: 0.2), value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Help card

struct ModeHelpCard: View {
    @EnvironmentObject private var app: AppModel
    let world: MoodWorld
    @Binding var isPresented: Bool

    var body: some View {
        let thing = app.t("底座或屏幕", "the base or the screen")
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { close() }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(app.t("怎么玩", "How to play")).font(.moodium(22, .bold))
                    Spacer()
                    GlassIconButton(symbol: "xmark", size: 34) { close() }
                }
                row("mode_icon_free", app.t("自由", "Free"),
                    app.t("想怎么按就怎么按，每一下都在把 Moodi 往外挤。", "Squeeze any way you like — every press pushes Moodi out."))
                row("mode_icon_rhythm", app.t("节奏", "Rhythm"),
                    app.t("光圈缩到能量环上时按一下\(thing)，连着按准，能量越攒越快。",
                          "Press \(thing) when the light ring meets the energy ring. Keep the streak for more energy."))
                row("mode_icon_breath", app.t("呼吸", "Breath"),
                    app.t("按住\(thing)慢慢吸气 3–5 秒，松开慢慢呼气。呼吸得越舒服，能量越多。",
                          "Hold \(thing) and breathe in for 3–5 s, then let go and breathe out. Calm breaths earn the most."))
            }
            .foregroundStyle(.white)
            .padding(22)
            .frame(width: 440)
            .glass(RoundedRectangle(cornerRadius: 28, style: .continuous), tint: Palette.smoke, amount: 0.6)
        }
    }

    private func row(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Image(asset: "mode_btn_base").resizable().frame(width: 38, height: 38)
                Image(asset: icon).resizable().frame(width: 19, height: 19)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.moodium(16, .bold))
                Text(body).font(.moodium(13)).foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func close() { withAnimation(.easeOut(duration: 0.25)) { isPresented = false } }
}

// MARK: - Rhythm guide (around the energy ring)

/// RhythmGuideView on the phone: a light ring closes in on the energy ring once per beat;
/// press when they meet. A splash on each hit, and a row of combo beads.
struct RhythmGuide: View {
    @ObservedObject var director: SqueezeDirector
    var accent: Color
    private let target: CGFloat = 168

    var body: some View {
        TimelineView(.animation) { context in
            let now = CACurrentMediaTime()
            let u = director.rhythmPhase(now)
            let hitAge = director.lastHit.map { context.date.timeIntervalSince($0.at) } ?? 99
            ZStack {
                // target
                Circle().stroke(.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))
                    .frame(width: target, height: target)
                // incoming
                Image(asset: "rhythm_ring_circle").resizable()
                    .frame(width: target, height: target)
                    .colorMultiply(accent)
                    .scaleEffect(1 + 0.85 * (1 - u))
                    .opacity(min(1, u * 2.5) * 0.9)
                // close to the beat: the target glows
                Circle().stroke(accent.opacity(0.75 * max(0, 1 - min(u, 1 - u) * 8)), lineWidth: 3)
                    .frame(width: target, height: target)
                    .blur(radius: 2)
                // hit splash
                if hitAge < 0.45, let hit = director.lastHit, hit.accuracy > 0 {
                    Image(asset: "rhythm_hit_splash").resizable()
                        .frame(width: target, height: target)
                        .colorMultiply(accent)
                        .scaleEffect(1 + hitAge * 0.9)
                        .opacity((1 - hitAge / 0.45) * (0.4 + 0.6 * hit.accuracy))
                }
                // combo beads
                HStack(spacing: 5) {
                    ForEach(0..<8, id: \.self) { i in
                        Image(asset: i < director.combo % 9 ? "rhythm_combo_bead_full" : "rhythm_combo_bead_empty")
                            .resizable().frame(width: 11, height: 11)
                            .colorMultiply(i < director.combo % 9 ? accent : .white)
                    }
                }
                .offset(y: target / 2 + 16)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Breath guide (around the energy ring)

/// BreathGuideView on the phone: a tide of light swells while you breathe in (hold),
/// with an arc that turns green in the good 3–5.5 s window, and ebbs while you breathe out.
struct BreathGuide: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var director: SqueezeDirector
    var accent: Color
    private let base: CGFloat = 168

    var body: some View {
        TimelineView(.animation) { context in
            let since = context.date.timeIntervalSince(director.breathStepAt)
            let held = director.heldSeconds()
            let (swell, label): (CGFloat, String?) = {
                switch director.breathStep {
                case .inhale: return (CGFloat(min(1, held / 4)), app.t("吸气", "Breathe in"))
                case .exhale: return (CGFloat(max(0, 1 - since / 5)), app.t("呼气", "Breathe out"))
                case .ready: return (CGFloat(0.06 + 0.04 * sin(since * 1.6)), nil)
                }
            }()
            ZStack {
                Image(asset: "glow_radial").resizable()
                    .frame(width: base * 1.9, height: base * 1.9)
                    .colorMultiply(accent)
                    .scaleEffect(0.75 + 0.55 * swell)
                    .opacity(0.25 + 0.5 * swell)
                Circle().stroke(.white.opacity(0.18), lineWidth: 2)
                    .frame(width: base, height: base)
                if director.breathStep == .inhale {
                    // 0–8 s around the ring; the good window (3–5.5 s) is marked
                    Circle().trim(from: 3 / 8, to: 5.5 / 8)
                        .stroke(Color(hex: 0x9BE8B4).opacity(0.45), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: base, height: base)
                    Circle().trim(from: 0, to: CGFloat(min(1, held / 8)))
                        .stroke(held >= 3 && held <= 5.5 ? Color(hex: 0x9BE8B4) : accent,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: base, height: base)
                        .shadow(color: accent, radius: 6)
                }
                if let label {
                    Text(label)
                        .font(.moodium(18, .bold))
                        .shadow(color: accent, radius: 8)
                        .offset(y: base / 2 + 20)
                        .transition(.opacity)
                        .id(label)
                }
                HStack(spacing: 5) {
                    ForEach(0..<6, id: \.self) { i in
                        Image(asset: i < min(6, director.breaths) ? "breath_count_dot_full" : "breath_count_dot_empty")
                            .resizable().frame(width: 10, height: 10)
                            .colorMultiply(i < director.breaths ? accent : .white)
                    }
                }
                .offset(y: -base / 2 - 14)
            }
        }
        .allowsHitTesting(false)
    }
}
