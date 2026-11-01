import SwiftUI

/// The home screen: Moodi greets you on the left (face follows today's mood, poke it),
/// and three glass cards on the right lead to the squeeze worlds, the wish chimes and the
/// mood journal. Every "back" in the app ends up here.
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
            let compact = geo.size.height < 430
            ZStack {
                MoodBackdrop(colors: backdropColors)
                TwinkleField(count: 26, color: Color(hex: 0xFFE6F3))

                HStack(spacing: max(20, geo.size.width * 0.04)) {
                    moodiColumn(compact: compact)
                        .frame(maxWidth: .infinity)
                    cards(compact: compact)
                        .frame(width: min(440, geo.size.width * 0.5))
                }
                .padding(.horizontal, 28)
                .padding(.top, compact ? 44 : 60)
                .padding(.bottom, 16)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)

                topBar

                if showJournal { MoodJournal(visits: visits, isPresented: $showJournal).transition(.opacity) }
                if showSettings { SettingsPanel(isPresented: $showSettings).transition(.opacity) }
            }
            .foregroundStyle(.white)
        }
        .onAppear {
            wishCount = WishStore.load().count
            visits = MoodLog.load()
            AudioDirector.shared.playMusic(app.lastWorld.bgm)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.1)) { appeared = true }
        }
        .onChange(of: app.moodCheck) { _, request in if request == nil { visits = MoodLog.load() } }
        #if MOODIUM_AUTOPILOT
        .onReceive(NotificationCenter.default.publisher(for: .init("AutopilotOpenJournal"))) { _ in showJournal = true }
        #endif
    }

    private var backdropColors: [Color] {
        let tint = app.preSample?.mood.tint ?? Palette.lavender
        return [tint, Palette.lavender, Color(hex: 0x4E7A5A)]
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack {
            HStack(spacing: 10) {
                Text("Moodium").font(.moodium(20, .bold))
                    .padding(.leading, 6)
                Spacer()
                GlassIconButton(symbol: app.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") { app.muted.toggle() }
                GlassIconButton(symbol: "gearshape.fill") { withAnimation { showSettings = true } }
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    // MARK: Moodi

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11: return app.t("早上好", "Good morning")
        case 11..<14: return app.t("中午好", "Hello")
        case 14..<18: return app.t("下午好", "Good afternoon")
        default: return app.t("晚上好", "Good evening")
        }
    }

    private var line: String {
        if let mood = app.preSample?.mood { return MoodCopy.text("rec.short.\(mood.rawValue)", app.language) }
        return app.t("今天也来捏一捏，放松一下吧～", "Come squeeze a little and unwind～")
    }

    private func moodiColumn(compact: Bool) -> some View {
        let size: CGFloat = compact ? 132 : 170
        return VStack(spacing: compact ? 10 : 16) {
            VStack(spacing: 3) {
                Text(greeting).font(.moodium(compact ? 24 : 28, .bold))
                Text(line).font(.moodium(14, .medium)).foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .glass(RoundedRectangle(cornerRadius: 20, style: .continuous), tint: app.preSample?.mood.tint, amount: 0.18)

            // the 3D Moodi (same model and animation as the rescue); tap to poke
            ZStack {
                Image(asset: "glow_radial").resizable()
                    .frame(width: size * 1.8, height: size * 1.8)
                    .colorMultiply(app.preSample?.mood.tint ?? Palette.lavender)
                    .opacity(0.55)
                    .allowsHitTesting(false)
                MoodiFigure(model: figure) { pokeMoodi() }
                    .frame(width: size * 1.5, height: size * 1.35)
            }
            .frame(height: size * 1.2)

            Button { app.moodCheck = .pre } label: {
                HStack(spacing: 7) {
                    if let sample = app.preSample {
                        Image(asset: sample.mood.icon).resizable().frame(width: 17, height: 17)
                        Text(MoodCopy.text("rec.today", app.language, ["mood": sample.mood.name(app.language)]))
                        Text("·").foregroundStyle(Palette.textMuted)
                        Text(app.t("再测一次", "Check again")).foregroundStyle(Palette.textMuted)
                    } else {
                        Image(asset: "icon_mood_neutral").resizable().frame(width: 17, height: 17)
                        Text(app.t("测测今天的心情", "How do you feel today?"))
                    }
                }
                .font(.moodium(14, .semibold))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .glass(tint: app.preSample?.mood.tint, amount: 0.3)
            }
            .buttonStyle(PressScaleStyle())
        }
    }

    private func pokeMoodi() {
        AudioDirector.shared.sfx("sfx_hop", volume: 0.5)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        if !AudioDirector.shared.isSpeaking, Bool.random() {
            AudioDirector.shared.voice("moodi_vo_K8a_\(app.language.rawValue)", clarity: 1)
        }
    }

    // MARK: Cards

    private func cards(compact: Bool) -> some View {
        let small: CGFloat = compact ? 96 : 120
        return VStack(spacing: 12) {
            // primary: the squeeze worlds
            Button { AudioDirector.shared.sfx("sfx_portal", volume: 0.45); app.stage = .select } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Image(asset: MoodWorld.nature.icon).resizable().scaledToFit().frame(width: 44)
                            .offset(x: 16, y: 10)
                        Image(asset: MoodWorld.candy.icon).resizable().scaledToFit().frame(width: 50)
                            .offset(x: -10, y: -6)
                    }
                    .frame(width: 78, height: 70)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.t("捏捏小世界", "Squeeze worlds")).font(.moodium(22, .bold))
                        Text(app.t("糖果世界 · 自然世界\n把掉进枕头的 Moodi 挤出来", "Candy World · Nature World\nSqueeze Moodi out of the pillow"))
                            .font(.moodium(13)).foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 18, weight: .bold))
                }
                .padding(.horizontal, 18).padding(.vertical, compact ? 14 : 18)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.candy.opacity(0.75), Palette.lavender.opacity(0.55), Palette.nature.opacity(0.55)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
                .glass(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .buttonStyle(PressScaleStyle())

            HStack(spacing: 12) {
                smallCard(icon: "wind", title: app.t("许愿风铃", "Wish chimes"),
                          detail: wishCount == 0 ? app.t("写下一个小心愿", "Write a little wish")
                                                 : app.t("已经挂了 \(wishCount) 个", "\(wishCount) hanging"),
                          tint: Color(hex: 0xFFB3D1), height: small) {
                    app.openWish(app.lastWorld)
                }
                smallCard(icon: "chart.line.uptrend.xyaxis", title: app.t("心情记录", "Mood journal"),
                          detail: journalDetail, tint: Color(hex: 0x9BE8B4), height: small) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showJournal = true }
                }
            }
        }
    }

    private var journalDetail: String {
        guard let last = visits.last(where: { $0.before != nil && $0.after != nil }), let b = last.before, let a = last.after else {
            return visits.isEmpty ? app.t("看看每次的心情变化", "See how each visit felt") : app.t("\(visits.count) 次记录", "\(visits.count) visits")
        }
        return "\(b.mood.name(app.language)) → \(a.mood.name(app.language))"
    }

    private func smallCard(icon: String, title: String, detail: String, tint: Color, height: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
                Spacer(minLength: 0)
                Text(title).font(.moodium(17, .bold))
                Text(detail).font(.moodium(12)).foregroundStyle(Palette.textMuted).lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
            .glass(RoundedRectangle(cornerRadius: 22, style: .continuous), tint: tint, amount: 0.12)
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Every visit kept by MoodLog (on this device only): world, mood before → after, time and squeezes.
struct MoodJournal: View {
    @EnvironmentObject private var app: AppModel
    let visits: [MoodVisit]
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { close() }
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
            .foregroundStyle(.white)
            .padding(22)
            .frame(width: 500)
            .glass(RoundedRectangle(cornerRadius: 28, style: .continuous), tint: Palette.smoke, amount: 0.6)
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
