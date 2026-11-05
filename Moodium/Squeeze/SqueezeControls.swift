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
    /// Shows the sensory-bag guide again.
    var onBagGuide: (() -> Void)? = nil

    var body: some View {
        let thing = app.t("感官袋或屏幕", "the bag or the screen")
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
                if let onBagGuide {
                    Button {
                        isPresented = false
                        onBagGuide()
                    } label: {
                        Label(app.t("感官袋怎么放？再看一遍", "How to use the sensory bag"), systemImage: "hand.point.down.fill")
                    }
                    .buttonStyle(GlassButtonStyle(compact: true))
                }
            }
            .foregroundStyle(.white)
            .padding(22)
            .frame(width: 440)
            .glass(RoundedRectangle(cornerRadius: 28, style: .continuous), tint: Palette.smoke, amount: 0.6)
            .offCrease()
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
/// press when they meet. Each press gets a word (perfect / nice / early / late), a splash on a
/// hit, and a row of streak beads on a dark pill so they read on the pale candy sky.
struct RhythmGuide: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var director: SqueezeDirector
    var accent: Color
    private let target: CGFloat = 168

    var body: some View {
        TimelineView(.animation) { context in
            let now = CACurrentMediaTime()
            let u = director.rhythmPhase(now)
            let near = max(0, 1 - min(u, 1 - u) * 8)          // 1 right on the beat
            let hitAge = director.lastHit.map { context.date.timeIntervalSince($0.at) } ?? 99
            let incoming = 1 + 0.85 * (1 - u)
            ZStack {
                // target
                Circle().stroke(.white.opacity(0.32 + 0.4 * near), style: StrokeStyle(lineWidth: 1.5 + 1.5 * near, dash: [3, 5]))
                    .frame(width: target, height: target)
                // incoming: a soft coloured band with a crisp white edge
                Image(asset: "rhythm_ring_circle").resizable()
                    .frame(width: target, height: target)
                    .colorMultiply(accent)
                    .scaleEffect(incoming)
                    .opacity(min(1, u * 2.5) * 0.9)
                Circle().stroke(.white.opacity(min(1, u * 2.5) * 0.85), lineWidth: 2)
                    .frame(width: target, height: target)
                    .scaleEffect(incoming)
                    .shadow(color: accent, radius: 4)
                // close to the beat: the target glows
                Circle().stroke(accent.opacity(0.9 * near), lineWidth: 5)
                    .frame(width: target, height: target)
                    .blur(radius: 3)
                // hit splash
                if hitAge < 0.45, let hit = director.lastHit, hit.accuracy > 0 {
                    Image(asset: "rhythm_hit_splash").resizable()
                        .frame(width: target, height: target)
                        .colorMultiply(accent)
                        .scaleEffect(1 + hitAge * 0.9)
                        .opacity((1 - hitAge / 0.45) * (0.4 + 0.6 * hit.accuracy))
                }
                streak.offset(y: target / 2 + 20)
                if hitAge < 0.8, let hit = director.lastHit {
                    grade(hit, age: hitAge).offset(y: target / 2 + 50)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Eight beads for the streak, and the count once it is going.
    private var streak: some View {
        let filled = director.combo == 0 ? 0 : (director.combo - 1) % 8 + 1
        return HStack(spacing: 5) {
            ForEach(0..<8, id: \.self) { i in
                Circle()
                    .fill(i < filled ? AnyShapeStyle(accent) : AnyShapeStyle(.white.opacity(0.28)))
                    .overlay(Circle().stroke(.white.opacity(i < filled ? 0.9 : 0.35), lineWidth: 1))
                    .frame(width: 10, height: 10)
                    .shadow(color: i < filled ? accent : .clear, radius: 3)
            }
            if director.combo >= 2 {
                Text("×\(director.combo)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(director.combo)))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Palette.ink.opacity(0.45)))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: director.combo)
    }

    private func grade(_ hit: RhythmHit, age: Double) -> some View {
        let (word, color): (String, Color) = {
            switch hit.grade {
            case .perfect: return (app.t("刚刚好", "Just right"), .white)
            case .good: return (app.t("很好", "Nice"), .white)
            case .early: return (app.t("等光圈再近一点", "Wait for the ring"), .white.opacity(0.85))
            case .late: return (app.t("跟着下一圈就好", "Catch the next one"), .white.opacity(0.85))
            }
        }()
        let pop = age < 0.15 ? 1.25 - age / 0.15 * 0.25 : 1
        return Text(word)
            .font(.moodium(hit.accuracy > 0 ? 18 : 15, hit.accuracy > 0 ? .bold : .semibold))
            .foregroundStyle(color)
            .shadow(color: hit.accuracy > 0 ? accent : .black.opacity(0.4), radius: 6)
            .padding(.horizontal, 10).padding(.vertical, 2)
            .background(Capsule().fill(Palette.ink.opacity(0.35)))
            .scaleEffect(pop)
            .offset(y: -CGFloat(age) * 10)
            .opacity(age < 0.55 ? 1 : max(0, 1 - (age - 0.55) / 0.25))
    }
}

// MARK: - Breath guide (around the energy ring)

/// BreathGuideView on the phone, like Apple's Breathe: a ring of light opens out while you
/// breathe in (hold) and closes while you breathe out, an arc counts the seconds and turns green
/// in the good 3–5.5 s window, and a pill below says what to do now with a seconds count.
struct BreathGuide: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var director: SqueezeDirector
    var accent: Color
    private let base: CGFloat = 168
    private let green = Color(hex: 0x9BE8B4)

    var body: some View {
        TimelineView(.animation) { context in
            let since = context.date.timeIntervalSince(director.breathStepAt)
            let held = director.heldSeconds()
            let swell: CGFloat = {
                switch director.breathStep {
                case .inhale: return CGFloat(ease(min(1, held / 4)))
                case .exhale: return CGFloat(ease(max(0, 1 - since / director.exhaleSeconds)))
                case .ready: return CGFloat(0.06 + 0.05 * sin(since * 1.2))
                }
            }()
            let inWindow = director.breathStep == .inhale && held >= 3 && held <= 5.5
            ZStack {
                // the opening ring: a soft band of colour with a white edge, growing with the breath
                Circle()
                    .fill(RadialGradient(colors: [.clear, accent.opacity(0.45), .clear],
                                         center: .center, startRadius: base * 0.42, endRadius: base * 0.5 * (1.15 + 0.5 * swell)))
                    .frame(width: base * (1.15 + 0.5 * swell), height: base * (1.15 + 0.5 * swell))
                Circle()
                    .stroke((inWindow ? green : .white).opacity(0.35 + 0.5 * swell), lineWidth: 2)
                    .frame(width: base * (1.0 + 0.42 * swell), height: base * (1.0 + 0.42 * swell))
                    .shadow(color: inWindow ? green : accent, radius: 6)
                Circle().stroke(.white.opacity(0.18), lineWidth: 2)
                    .frame(width: base, height: base)
                if director.breathStep == .inhale {
                    // 0–8 s around the ring; the good window (3–5.5 s) is marked
                    Circle().trim(from: 3 / 8, to: 5.5 / 8)
                        .stroke(green.opacity(0.6), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: base, height: base)
                    Circle().trim(from: 0, to: CGFloat(min(1, held / 8)))
                        .stroke(inWindow ? green : accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: base, height: base)
                        .shadow(color: inWindow ? green : accent, radius: 6)
                }
                pill(held: held, since: since, inWindow: inWindow)
                    .offset(y: base / 2 + 26)
            }
        }
        .allowsHitTesting(false)
    }

    /// What to do now, with the seconds, and the breaths taken so far.
    private func pill(held: Double, since: Double, inWindow: Bool) -> some View {
        let (word, color): (String, Color) = {
            switch director.breathStep {
            case .inhale:
                if held < 3 { return (app.t("吸气 \(Int(held) + 1)", "Breathe in \(Int(held) + 1)"), .white) }
                if held <= 5.5 { return (app.t("松开，呼气", "Let go, breathe out"), green) }
                return (app.t("可以松开啦", "Let go now"), Color(hex: 0xFFE3A3))
            case .exhale:
                // a long, slow breath out calms the body most: count it down
                let left = Int(ceil(director.exhaleSeconds - since))
                if left > 0 { return (app.t("慢慢呼气 \(left)", "Breathe out \(left)"), .white) }
                return (app.t("准备好了再吸气", "Breathe in when ready"), .white.opacity(0.85))
            case .ready: return (app.t("按住，吸气", "Hold to breathe in"), .white.opacity(0.85))
            }
        }()
        return HStack(spacing: 8) {
            Text(word)
                .font(.moodium(17, .bold))
                .foregroundStyle(color)
                .monospacedDigit()
                .contentTransition(.numericText())
                .id(director.breathStep == .inhale && held >= 3 ? "window"
                    : director.breathStep == .exhale && since >= director.exhaleSeconds ? "rest" : "\(director.breathStep)")
            if director.breaths > 0 {
                HStack(spacing: 4) {
                    ForEach(0..<min(6, max(3, director.breaths)), id: \.self) { i in
                        Circle().fill(i < director.breaths ? AnyShapeStyle(accent) : AnyShapeStyle(.white.opacity(0.28)))
                            .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 0.8))
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Capsule().fill(Palette.ink.opacity(0.48)))
        .overlay(Capsule().stroke((inWindow ? green : .white).opacity(inWindow ? 0.8 : 0.18), lineWidth: 1))
        .animation(.easeOut(duration: 0.25), value: word)
    }

    private func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}
