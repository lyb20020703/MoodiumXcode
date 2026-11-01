import SwiftUI

/// What the mood check is asking.
enum MoodCheckRequest: Equatable {
    /// Before choosing a world: ends with a recommendation.
    case pre
    /// After leaving a world: ends with a before / now comparison.
    case post(MoodVisitMetrics)
}

struct MoodVisitMetrics: Equatable {
    var world: MoodWorld
    var seconds: Double
    var squeezes: Int
    var mode: SqueezeMode
    /// Moodi was squeezed all the way out.
    var completed = false
}

/// The visionOS mood check panel on the phone: a colour plate you drag Moodi across
/// (valence left → right, energy bottom → top), a confirmation, then either Moodi's
/// world recommendation or the before / now comparison.
struct MoodCheckView: View {
    @EnvironmentObject private var app: AppModel
    let request: MoodCheckRequest

    private enum Step { case plate, confirm, result }
    @State private var step = Step.plate
    @State private var point = CGPoint.zero
    @State private var dragging = false
    @State private var touched = false
    @State private var appeared = false
    /// The answer from before the visit (kept here: confirming replaces app.preSample).
    @State private var before: MoodSample?

    private var mood: MoodKind { MoodKind.classify(point) }
    private var isPost: Bool { if case .post = request { return true } else { return false } }

    var body: some View {
        GeometryReader { geo in
            let plate = min(geo.size.height * 0.74, geo.size.width * 0.36, 330)
            ZStack {
                backdrop
                HStack(spacing: max(24, geo.size.width * 0.05)) {
                    plateView(size: plate)
                        .frame(width: plate + 70, height: plate + 56)
                    side
                        .frame(maxWidth: 380, alignment: .leading)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !isPost && step != .result {
                    Button(MoodCopy.text("skip", app.language)) { finish(nil) }
                        .buttonStyle(.plain)
                        .font(.moodium(15, .medium))
                        .foregroundStyle(Palette.textMuted)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .glass(shadow: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 14).padding(.trailing, 20)
                }
            }
            .foregroundStyle(Palette.ink)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.97)
        }
        .onAppear {
            if case .post = request, let pre = app.preSample { point = pre.point; before = pre }
            withAnimation(.easeOut(duration: 0.45)) { appeared = true }
            #if MOODIUM_AUTOPILOT
            let env = ProcessInfo.processInfo.environment
            if let m = env["MOODPICK"].flatMap(MoodKind.init(rawValue:)) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { pick(m) }
                if env["MOODCONFIRM"] != nil { DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { confirm() } }
            }
            #endif
        }
    }

    // MARK: Backdrop

    private var backdrop: some View {
        ZStack {
            MoodBackdrop(colors: [mood.tint, Palette.lavender, Palette.sky])
            TwinkleField(count: 18)
        }
        .ignoresSafeArea()
    }

    // MARK: Plate

    private func plateView(size: CGFloat) -> some View {
        let r = size / 2
        let effective = r * 0.8   // where the token can go (MoodCheckPlate.EffectiveRadius ≈ 0.8 of the disc)
        let token = CGPoint(x: point.x * effective, y: -point.y * effective)
        return ZStack {
            // soft light in the mood colour
            IridescentOrb(size: size * 1.3, tint: touched ? mood.tint : nil)
                .opacity(0.8)
            Image(asset: "mood_plate_well").resizable().frame(width: size * 1.12, height: size * 1.12).offset(y: 8)
                .opacity(0.25)
            Image(asset: "mood_plate_colorfield").resizable().frame(width: size, height: size)
                .opacity(0.92)
            Image(asset: "zone_ring_dashed").resizable()
                .frame(width: effective * 2 * MoodKind.neutralRadius * 1.08, height: effective * 2 * MoodKind.neutralRadius * 1.08)
                .opacity(0.7)
            ForEach([MoodKind.happy, .calm, .low, .tense]) { m in
                let p = m.preset
                Image(asset: "mood_glyph_\(m.rawValue)").resizable()
                    .frame(width: size * 0.1, height: size * 0.1)
                    .opacity(touched && mood == m ? 0.95 : 0.42)
                    .scaleEffect(touched && mood == m ? 1.15 : 1)
                    .offset(x: p.x * effective * 1.02, y: -p.y * effective * 1.02)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: mood)
            }
            Image(asset: "mood_plate_lens").resizable().frame(width: size, height: size)
                .allowsHitTesting(false)

            // Moodi token
            ZStack {
                Image(asset: "mood_token_halo").resizable()
                    .frame(width: size * 0.42, height: size * 0.42)
                    .colorMultiply(mood.tint)
                    .opacity(dragging ? 1 : 0.8)
                Image(asset: mood.moodiFace).resizable().scaledToFit()
                    .frame(width: size * 0.25)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
                    .id(mood)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            .scaleEffect(dragging ? 1.12 : 1)
            .offset(x: token.x, y: token.y)
            .animation(dragging ? .interactiveSpring(response: 0.15, dampingFraction: 0.85) : .spring(response: 0.45, dampingFraction: 0.72), value: point)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragging)
            .animation(.easeOut(duration: 0.2), value: mood)

            axisLabel("axis.up").offset(y: -r - 16)
            axisLabel("axis.down").offset(y: r + 16)
            axisLabel("axis.left").rotationEffect(.degrees(-90)).offset(x: -r - 18)
            axisLabel("axis.right").rotationEffect(.degrees(90)).offset(x: r + 18)
        }
        .frame(width: size, height: size)
        .contentShape(Circle().inset(by: -20))
        .gesture(step == .result ? nil : DragGesture(minimumDistance: 0)
            .onChanged { v in
                let c = CGPoint(x: (v.location.x - r) / effective, y: -(v.location.y - r) / effective)
                let len = max(1, hypot(c.x, c.y))
                if !dragging { AudioDirector.shared.sfx("sfx_hop", volume: 0.25) }
                dragging = true; touched = true
                point = CGPoint(x: c.x / len, y: c.y / len)
                if step == .confirm { step = .plate }
            }
            .onEnded { _ in
                dragging = false
                AudioDirector.shared.sfx("sfx_squish", volume: 0.3)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = .confirm }
            })
    }

    private func axisLabel(_ key: String) -> some View {
        Text(MoodCopy.text(key, app.language))
            .font(.moodium(12, .semibold))
            .foregroundStyle(Palette.textMuted)
            .fixedSize()
    }

    // MARK: Side column

    @ViewBuilder private var side: some View {
        switch step {
        case .plate, .confirm: question.transition(.opacity)
        case .result:
            if case .post(let metrics) = request { comparison(metrics).transition(.opacity.combined(with: .move(edge: .trailing))) }
            else { recommendation.transition(.opacity.combined(with: .move(edge: .trailing))) }
        }
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(MoodCopy.text("plate.kicker", app.language))
                .font(.moodium(14, .semibold)).foregroundStyle(Palette.lilac)
            Text(MoodCopy.text(isPost ? "plate.title.post" : "plate.title.pre", app.language))
                .font(.moodium(30, .heavy))
                .fixedSize(horizontal: false, vertical: true)

            // current mood
            HStack(spacing: 8) {
                Image(asset: mood.icon).resizable().frame(width: 20, height: 20)
                Text(touched ? mood.label(app.language) : MoodCopy.text("plate.hint", app.language))
                    .font(.moodium(15, .medium))
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .glass(tint: touched ? mood.tint : nil, amount: 0.3, shadow: false)
            .animation(.easeOut(duration: 0.2), value: mood)

            // quick picks
            HStack(spacing: 6) {
                ForEach([MoodKind.happy, .calm, .neutral, .low, .tense]) { m in
                    Button { pick(m) } label: {
                        VStack(spacing: 3) {
                            Image(asset: m.moodiFace).resizable().scaledToFit().frame(width: 34)
                            Text(m.name(app.language)).font(.moodium(11, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(width: 58, height: 62)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(m.tint.opacity(touched && mood == m ? 0.32 : 0)))
                        .glass(RoundedRectangle(cornerRadius: 16, style: .continuous), shadow: false)
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }

            if step == .confirm {
                VStack(alignment: .leading, spacing: 10) {
                    Text(MoodCopy.text("confirm.title", app.language, ["mood": mood.name(app.language)]))
                        .font(.moodium(17, .semibold))
                    HStack(spacing: 10) {
                        Button(MoodCopy.text("confirm.adjust", app.language)) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { step = .plate }
                        }
                        .buttonStyle(GlassButtonStyle())
                        Button(MoodCopy.text("confirm.yes", app.language)) { confirm() }
                            .buttonStyle(GlassButtonStyle(tint: mood.tint.opacity(0.9), prominent: true))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var recommendation: some View {
        let world = mood.recommendedWorld
        let other: MoodWorld = world == .candy ? .nature : .candy
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(asset: mood.icon).resizable().frame(width: 18, height: 18)
                Text(MoodCopy.text("rec.today", app.language, ["mood": mood.name(app.language)]))
                    .font(.moodium(14, .semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .glass(tint: mood.tint, amount: 0.3, shadow: false)

            Text(MoodCopy.text("rec.\(mood.rawValue)", app.language))
                .font(.moodium(22, .bold))
                .fixedSize(horizontal: false, vertical: true)

            // the recommended world
            HStack(spacing: 14) {
                Image(asset: world.icon).resizable().scaledToFit().frame(width: 56, height: 56)
                    .shadow(color: world.accent.opacity(0.7), radius: 12)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(asset: "icon_star").resizable().frame(width: 13, height: 13)
                        Text(MoodCopy.text("tag.pick", app.language)).font(.moodium(12, .bold))
                    }
                    .foregroundStyle(world.accent)
                    Text(world.name(app.language)).font(.moodium(19, .bold))
                    Text(MoodCopy.text("rec.mode", app.language, ["mode": mood.recommendedMode.name(app.language)]))
                        .font(.moodium(13)).foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .glass(RoundedRectangle(cornerRadius: 22, style: .continuous), tint: world.accent, amount: 0.2)

            HStack(spacing: 10) {
                Button { finish(world) } label: {
                    Label(MoodCopy.text("rec.cta", app.language, ["world": world.name(app.language)]), systemImage: "arrow.right")
                        .labelStyle(TrailingIconLabel())
                }
                .buttonStyle(GlassButtonStyle(tint: world.accent, prominent: true))
                Button(MoodCopy.text("rec.retry", app.language)) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = .plate }
                }
                .buttonStyle(GlassButtonStyle())
            }
            Button { finish(other) } label: {
                Text(MoodCopy.text("rec.other", app.language)).underline()
            }
            .buttonStyle(.plain)
            .font(.moodium(13)).foregroundStyle(Palette.textMuted)
        }
    }

    private func comparison(_ m: MoodVisitMetrics) -> some View {
        let after = MoodSample(point)
        let result = before.map { MoodSample.compare(before: $0, after: after) } ?? .same
        let key = result == .better ? "compare.better" : result == .worse ? "compare.worse" : "compare.same"
        return VStack(alignment: .leading, spacing: 14) {
            Text(MoodCopy.text("compare.kicker", app.language, ["world": m.world.name(app.language)]))
                .font(.moodium(14, .semibold)).foregroundStyle(Palette.lilac)
            Text(MoodCopy.text(key, app.language))
                .font(.moodium(23, .bold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                if let before { moodBadge(before.mood, MoodCopy.text("compare.before", app.language)) }
                Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.textMuted)
                moodBadge(after.mood, MoodCopy.text("compare.now", app.language))
            }
            HStack(spacing: 16) {
                metric(MoodCopy.text("compare.time", app.language),
                       app.language == .zh ? String(format: "%.1f 分钟", m.seconds / 60) : String(format: "%.1f min", m.seconds / 60))
                metric(MoodCopy.text("compare.squeezes", app.language), app.language == .zh ? "\(m.squeezes) 次" : "\(m.squeezes)")
            }
            Label(MoodCopy.text("compare.privacy", app.language), systemImage: "lock.fill")
                .font(.moodium(12)).foregroundStyle(Palette.textMuted)
            Button(MoodCopy.text("compare.continue", app.language)) { finish(nil) }
                .buttonStyle(GlassButtonStyle(tint: after.mood.tint.opacity(0.9), prominent: true))
        }
    }

    private func moodBadge(_ m: MoodKind, _ caption: String) -> some View {
        VStack(spacing: 4) {
            Image(asset: m.moodiFace).resizable().scaledToFit().frame(width: 48)
                .background(Circle().fill(m.tint.opacity(0.3)).frame(width: 58, height: 58))
            Text("\(caption) · \(m.name(app.language))").font(.moodium(12, .semibold)).foregroundStyle(Palette.textMuted)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.moodium(12)).foregroundStyle(Palette.textMuted)
            Text(value).font(.moodium(18, .bold))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glass(RoundedRectangle(cornerRadius: 16, style: .continuous), shadow: false)
    }

    // MARK: Actions

    private func pick(_ m: MoodKind) {
        AudioDirector.shared.sfx("sfx_hop", volume: 0.3)
        touched = true
        point = m.preset
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = .confirm }
    }

    private func confirm() {
        let sample = MoodSample(point)
        AudioDirector.shared.sfx("sfx_chime", volume: 0.45)
        if case .post(let m) = request {
            app.recordPostSample(sample, metrics: m)
        } else {
            app.preSample = sample
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = .result }
    }

    /// Close. `world` = the world to show in the carousel.
    private func finish(_ world: MoodWorld?) {
        if let world {
            app.lastWorld = world
            // from the home screen, "go to Candy World" opens the worlds with that one in front
            if app.stage == .home { app.stage = .select }
        }
        withAnimation(.easeOut(duration: 0.3)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { app.closeMoodCheck() }
    }
}

/// Small press-scale for picture buttons.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

/// Text first, icon after.
struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}
