import SwiftUI

/// The home screen, in the soft lavender style: a big greeting and a row of mood faces on the
/// left, the 3D Moodi on an iridescent orb in the middle, and floating cards on the right for
/// the squeeze worlds, the wish chimes and the mood journal. Every "back" ends up here.
struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showSettings = false
    @State private var showJournal = false
    @State private var figure = MoodiFigureModel()
    @State private var appeared = false
    @State private var wishCount = 0
    @State private var visits: [MoodVisit] = []

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height, w = geo.size.width
            ZStack {
                MoodBackdrop()
                TwinkleField(count: 18)

                HStack(alignment: .center, spacing: 0) {
                    leftColumn(h: h)
                        .frame(width: w * 0.36, alignment: .leading)
                    moodiStage(size: min(h * 0.64, w * 0.24))
                        .frame(width: w * 0.27)
                    cards(h: h, width: max(260, w * 0.37 - 52))
                        .frame(width: max(260, w * 0.37 - 52))
                }
                .padding(.leading, 34).padding(.trailing, 18)
                .padding(.top, 34)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)

                topBar

                if showJournal { MoodJournal(visits: visits, isPresented: $showJournal).transition(.opacity) }
                if showSettings { SettingsPanel(isPresented: $showSettings).transition(.opacity) }
            }
            .foregroundStyle(Palette.ink)
        }
        .onAppear {
            wishCount = WishStore.load().count
            visits = MoodLog.load()
            AudioDirector.shared.playMusic(app.lastWorld.bgm)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.1)) { appeared = true }
        }
        .onChange(of: app.moodCheck) { _, request in if request == nil { visits = MoodLog.load() } }
        #if MOODIUM_AUTOPILOT
        .onReceive(NotificationCenter.default.publisher(for: .init("AutopilotOpenJournal"))) { _ in showJournal = true }
        #endif
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack {
            HStack(spacing: 10) {
                Spacer()
                GlassIconButton(symbol: app.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 42) { app.muted.toggle() }
                GlassIconButton(symbol: "gearshape.fill", size: 42) { withAnimation { showSettings = true } }
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    // MARK: Left: greeting + mood faces

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11: return app.t("早上好呀", "Good morning")
        case 11..<14: return app.t("中午好呀", "Hello there")
        case 14..<18: return app.t("下午好呀", "Good afternoon")
        default: return app.t("晚上好呀", "Good evening")
        }
    }

    private var subline: String {
        if let mood = app.preSample?.mood { return MoodCopy.text("rec.short.\(mood.rawValue)", app.language) }
        return app.t("今天也一起捏一捏，\n把心事放轻一点", "Let's squeeze a little\nand let today feel lighter")
    }

    private func leftColumn(h: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(LinearGradient(colors: [Palette.blush, Palette.lilac], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                    .overlay(Image(asset: "moodi_happy").resizable().scaledToFit().padding(3))
                Text("Moodium").font(.moodium(15, .bold)).foregroundStyle(Palette.textMuted)
            }
            Text(greeting)
                .font(.moodium(h < 430 ? 38 : 46, .heavy))
                .padding(.top, 14)
            Text(subline)
                .font(.moodium(h < 430 ? 19 : 22, .regular))
                .foregroundStyle(Palette.textMuted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .id(subline)
            Spacer(minLength: 12)
            moodFaces
            Spacer(minLength: 8)
        }
        .frame(maxHeight: .infinity)
    }

    /// "How are you feeling today?" with five Moodi faces: one tap records today's mood.
    private var moodFaces: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(app.t("今天心情怎么样？", "How are you feeling today?")).font(.moodium(15, .semibold))
                Spacer()
                Button { app.moodCheck = .pre } label: {
                    HStack(spacing: 2) {
                        Text(app.t("细调", "Fine-tune"))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(.moodium(12, .semibold)).foregroundStyle(Palette.lilac)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                ForEach([MoodKind.happy, .calm, .neutral, .low, .tense]) { m in
                    let selected = app.preSample?.mood == m
                    Button { pick(m) } label: {
                        VStack(spacing: 2) {
                            Image(asset: m.moodiFace).resizable().scaledToFit().frame(width: 36)
                            Text(m.name(app.language)).font(.moodium(10.5, .semibold))
                                .foregroundStyle(selected ? Palette.ink : Palette.textMuted)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(width: 52, height: 62)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(selected ? m.tint.opacity(0.55) : .clear))
                        .glass(RoundedRectangle(cornerRadius: 18, style: .continuous), shadow: selected)
                        .scaleEffect(selected ? 1.06 : 1)
                    }
                    .buttonStyle(PressScaleStyle())
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
                }
            }
        }
        .padding(14)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous), tint: .white, amount: 0.2)
        .frame(maxWidth: 318)
    }

    private func pick(_ m: MoodKind) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        AudioDirector.shared.sfx("sfx_chime", volume: 0.35)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { app.preSample = MoodSample(m.preset) }
        _ = figure.poke()
    }

    // MARK: Middle: Moodi on an orb

    private func moodiStage(size: CGFloat) -> some View {
        ZStack {
            IridescentOrb(size: size * 1.05, tint: app.preSample?.mood.tint)
            MoodiFigure(model: figure) { pokeMoodi() }
                .frame(width: size * 1.25, height: size * 1.2)
        }
        .frame(height: size * 1.2)
    }

    private func pokeMoodi() {
        AudioDirector.shared.sfx("sfx_hop", volume: 0.5)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        if !AudioDirector.shared.isSpeaking, Bool.random() {
            AudioDirector.shared.voice("moodi_vo_K8a_\(app.language.rawValue)", clarity: 1)
        }
    }

    // MARK: Right: floating cards

    private func cards(h: CGFloat, width: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                worldsCard
                    .rotationEffect(.degrees(-3))
                    .offset(x: 6, y: h * 0.06 + 4 * sin(t * 0.9))
                journalCard
                    .rotationEffect(.degrees(-4))
                    .offset(x: 0, y: h * 0.52 + 4 * sin(t * 1.3 + 2))
                wishCard
                    .rotationEffect(.degrees(5))
                    .offset(x: width - 128, y: h * 0.48 + 4 * sin(t * 1.1 + 1))
            }
            .frame(width: width, height: h * 0.86, alignment: .topLeading)
        }
    }

    private var worldsCard: some View {
        Button { AudioDirector.shared.sfx("sfx_portal", volume: 0.45); app.stage = .select } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(app.t("开始", "Start")).font(.moodium(12, .semibold)).foregroundStyle(Palette.textMuted)
                    Spacer()
                    HStack(spacing: -10) {
                        Image(asset: MoodWorld.candy.icon).resizable().scaledToFit().frame(width: 30)
                        Image(asset: MoodWorld.nature.icon).resizable().scaledToFit().frame(width: 26)
                    }
                }
                Text(app.t("捏捏小世界", "Squeeze worlds")).font(.moodium(24, .heavy))
                Text(app.t("把掉进枕头的 Moodi 挤出来", "Squeeze Moodi out of the pillow"))
                    .font(.moodium(13)).foregroundStyle(Palette.textMuted)
                HStack {
                    Text(app.t("糖果 · 自然", "Candy · Nature")).font(.moodium(12, .semibold)).foregroundStyle(Palette.textMuted)
                    Spacer()
                    Circle().fill(Palette.ink).frame(width: 34, height: 34)
                        .overlay(Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                }
                .padding(.top, 2)
            }
            .padding(16)
            .frame(width: 236)
            .glass(RoundedRectangle(cornerRadius: 26, style: .continuous), tint: .white, amount: 0.45)
        }
        .buttonStyle(PressScaleStyle())
    }

    private var wishCard: some View {
        Button { app.openWish(app.lastWorld) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "wind").font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 0)
                Text(app.t("许愿风铃", "Wish chimes")).font(.moodium(18, .heavy))
                Text(wishCount == 0 ? app.t("写下一个小心愿", "Write a little wish") : app.t("已经挂了 \(wishCount) 个", "\(wishCount) hanging"))
                    .font(.moodium(12, .medium)).opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(15)
            .frame(width: 124, height: 112, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xC59AF0), Palette.lilac, Color(hex: 0x8C8BF2)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.55), lineWidth: 1))
            .shadow(color: Palette.lilac.opacity(0.45), radius: 16, y: 8)
        }
        .buttonStyle(PressScaleStyle())
    }

    private var journalCard: some View {
        Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showJournal = true } } label: {
            VStack(alignment: .leading, spacing: 8) {
                MoodRing(visits: visits).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.t("心情记录", "Mood journal")).font(.moodium(15, .heavy))
                    Text(journalDetail).font(.moodium(11.5, .medium)).foregroundStyle(Palette.textMuted).lineLimit(1)
                }
            }
            .padding(13)
            .frame(width: 128, height: 112, alignment: .leading)
            .glass(RoundedRectangle(cornerRadius: 22, style: .continuous), tint: .white, amount: 0.45)
        }
        .buttonStyle(PressScaleStyle())
    }

    private var journalDetail: String {
        guard let last = visits.last(where: { $0.before != nil && $0.after != nil }), let b = last.before, let a = last.after else {
            return visits.isEmpty ? app.t("看看心情的变化", "See how you felt") : app.t("\(visits.count) 次记录", "\(visits.count) visits")
        }
        return "\(b.mood.name(app.language)) → \(a.mood.name(app.language))"
    }
}

/// Little ring of the latest visits, each arc in the colour of the mood afterwards.
struct MoodRing: View {
    let visits: [MoodVisit]
    var body: some View {
        let recent = Array(visits.suffix(8))
        ZStack {
            Circle().stroke(Palette.lilac.opacity(0.15), lineWidth: 7)
            ForEach(Array(recent.enumerated()), id: \.offset) { i, v in
                let n = Double(max(recent.count, 1))
                Circle()
                    .trim(from: Double(i) / n + 0.01, to: Double(i + 1) / n - 0.01)
                    .stroke((v.after?.mood ?? v.before?.mood ?? .neutral).tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text("\(visits.count)").font(.moodium(13, .heavy)).foregroundStyle(Palette.ink)
        }
    }
}

/// Every visit kept by MoodLog (on this device only): world, mood before → after, time and squeezes.
struct MoodJournal: View {
    @EnvironmentObject private var app: AppModel
    let visits: [MoodVisit]
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.18).ignoresSafeArea().onTapGesture { close() }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(app.t("心情记录", "Mood journal")).font(.moodium(22, .bold))
                    Spacer()
                    GlassIconButton(symbol: "xmark", size: 34) { close() }
                }
                if visits.isEmpty {
                    Text(app.t("还没有记录。进小世界前测一测心情，救出 Moodi 离开时再测一次，这里就会记下变化。",
                               "Nothing yet. Check your mood before a world and again when you leave after freeing Moodi, and the change shows up here."))
                        .font(.moodium(14)).foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(Array(visits.reversed().enumerated()), id: \.offset) { _, v in row(v) }
                        }
                    }
                    .frame(maxHeight: 250)
                }
                Label(MoodCopy.text("compare.privacy", app.language), systemImage: "lock.fill")
                    .font(.moodium(12)).foregroundStyle(Palette.textMuted)
            }
            .foregroundStyle(Palette.ink)
            .padding(22)
            .frame(width: 500)
            .glass(RoundedRectangle(cornerRadius: 28, style: .continuous), tint: .white, amount: 0.35)
        }
    }

    private func row(_ v: MoodVisit) -> some View {
        let world = MoodWorld(rawValue: v.world) ?? .candy
        let date = v.after?.date ?? v.before?.date ?? Date()
        return HStack(spacing: 12) {
            Image(asset: world.icon).resizable().scaledToFit().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(date.formatted(.dateTime.month().day().hour().minute())).font(.moodium(13, .semibold))
                Text(app.t(String(format: "%@ · %.1f 分钟 · 捏了 %d 次", world.name(.zh), v.seconds / 60, v.squeezes),
                           String(format: "%@ · %.1f min · %d squeezes", world.name(.en), v.seconds / 60, v.squeezes)))
                    .font(.moodium(12)).foregroundStyle(Palette.textMuted)
            }
            Spacer()
            face(v.before?.mood)
            Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textMuted)
            face(v.after?.mood)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glass(RoundedRectangle(cornerRadius: 16, style: .continuous), shadow: false)
    }

    @ViewBuilder private func face(_ mood: MoodKind?) -> some View {
        if let mood {
            Image(asset: mood.moodiFace).resizable().scaledToFit().frame(width: 30)
                .background(Circle().fill(mood.tint.opacity(0.35)).frame(width: 34, height: 34))
        } else {
            Text("–").font(.moodium(14)).foregroundStyle(Palette.textMuted).frame(width: 30)
        }
    }

    private func close() { withAnimation(.easeOut(duration: 0.25)) { isPresented = false } }
}
