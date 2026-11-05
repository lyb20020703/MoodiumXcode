import SwiftUI

/// Wish chimes screen. Layout of the writing step follows the visionOS WishPresetPanel:
/// preset chips on the left, the paper strip (under its bell) in the middle, Release above
/// Rewrite on the right. Hung wishes sway in a row along the top.
struct WishView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.screenMargins) private var m
    @Environment(\.crease) private var crease
    @StateObject private var wish: WishController
    @State private var flyStart: Date?
    @State private var showSettings = false
    let world: MoodWorld

    init(world: MoodWorld) {
        self.world = world
        _wish = StateObject(wrappedValue: WishController(world: world))
    }

    private let bellW: CGFloat = 54
    private var chimeStripW: CGFloat { bellW * 166 / 360 }
    private var chimeBellH: CGFloat { bellW * 450 / 360 }
    private var chimeH: CGFloat { chimeBellH - bellW * 0.03 + chimeStripW * 27.5 / 8.5 }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                backdrop
                garden(size).opacity(wish.mode == .writing ? 0 : 1)
                if wish.mode == .garden { gardenPanel(size).transition(.opacity) }
                if wish.mode == .writing { writing(size).transition(.opacity.combined(with: .scale(scale: 0.96))) }
                if let record = wish.flying { flight(record, size) }
                topBar
                subtitle
                if showSettings { SettingsPanel(isPresented: $showSettings).transition(.opacity) }
            }
            .foregroundStyle(.white)
            .animation(.easeInOut(duration: 0.35), value: wish.mode)
        }
        .onAppear {
            AudioDirector.shared.playMusic(world.bgm)
            wish.start(language: app.language)
        }
        .onDisappear { wish.stop() }
    }

    // MARK: Background

    private var backdrop: some View {
        Color.clear.overlay {
            ZStack {
                Palette.ink
                if let image = Res.image(world.backdrop) {
                    Image(uiImage: image).resizable().scaledToFill().blur(radius: 2).scaleEffect(1.04)
                }
                LinearGradient(colors: [Palette.ink.opacity(0.35), Palette.ink.opacity(0.2), Palette.ink.opacity(0.75)],
                               startPoint: .top, endPoint: .bottom)
                TwinkleField(count: 24, color: .white.opacity(0.7))
            }
        }
        .clipped()
        .ignoresSafeArea()
    }

    private var topBar: some View {
        VStack {
            HStack(spacing: 10) {
                GlassIconButton(symbol: "chevron.left") { back() }
                if wish.mode != .garden || wish.records.isEmpty {
                    HStack(spacing: 6) {
                        Image(asset: world.icon).resizable().scaledToFit().frame(width: 20, height: 20)
                        Text(app.t("许愿风铃", "Wish Chimes")).font(.moodium(15, .semibold))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .glass(tint: world.accent, amount: 0.15)
                }
                Spacer()
                GlassIconButton(symbol: app.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") { app.muted.toggle() }
                GlassIconButton(symbol: "gearshape.fill") { withAnimation { showSettings = true } }
            }
            Spacer()
        }
        .padding(m.insets)
    }

    private var subtitle: some View {
        VStack {
            Spacer()
            if let line = wish.subtitle {
                HStack(spacing: 8) {
                    Image(asset: "moodi_happy").resizable().frame(width: 24, height: 24)
                    Text(line).font(.moodium(15, .semibold))
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
                .glass(tint: Palette.lavender, amount: 0.2)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .id(line)
            }
        }
        .padding(.bottom, m.bottom)
        .allowsHitTesting(false)
    }

    // MARK: Garden

    private func slots(_ size: CGSize) -> (count: Int, x: (Int) -> CGFloat) {
        let left: CGFloat = 96, right: CGFloat = size.width - 40
        let count = max(1, Int((right - left) / 70))
        let step = (right - left) / CGFloat(count)
        return (count, { left + step * (CGFloat($0) + 0.5) })
    }

    private func garden(_ size: CGSize) -> some View {
        let s = slots(size)
        let shown = wish.visible(count: s.count)
        let offset = wish.records.count - shown.count
        return ZStack(alignment: .topLeading) {
            // the line they hang from
            Capsule().fill(.white.opacity(0.25)).frame(height: 1.5).offset(y: 4)
            ForEach(Array(shown.enumerated()), id: \.element.id) { k, record in
                let i = offset + k
                HangingChime(world: world, record: record, width: bellW)
                    .rotationEffect(.radians(i < wish.angles.count ? wish.angles[i] : 0), anchor: .top)
                    .frame(width: bellW, height: chimeH)
                    .contentShape(Rectangle())
                    .onTapGesture { wish.tapChime(i) }
                    .position(x: s.x(k), y: chimeH / 2 - 4)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func gardenPanel(_ size: CGSize) -> some View {
        VStack(spacing: 10) {
            Text(app.t("许愿风铃", "Wish Chimes")).font(.moodium(24, .bold))
            Text(wish.records.isEmpty
                 ? app.t("写下一件想放下的事，或者一个小心愿", "Write down something to let go of, or a little wish")
                 : app.t("这里已经挂了 \(wish.records.count) 个心愿", wish.records.count == 1 ? "1 wish is hanging here" : "\(wish.records.count) wishes are hanging here"))
                .font(.moodium(15)).foregroundStyle(Palette.textMuted)
            Button { wish.beginWriting() } label: {
                Label(app.t("写一张心愿", "Write a wish"), systemImage: "pencil.line")
            }
            .buttonStyle(GlassButtonStyle(tint: world.accent, prominent: true))
            .padding(.top, 4)
            if !wish.records.isEmpty {
                Text(app.t("点一下风铃会响；倾斜手机它们会摇，摇一摇手机全部响起来",
                           "Tap a chime to ring it. Tilt the phone to sway them, shake to ring them all"))
                    .font(.moodium(12)).foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 26).padding(.vertical, 18)
        .glass(RoundedRectangle(cornerRadius: 26, style: .continuous), tint: Palette.smoke, amount: 0.45)
        .frame(maxWidth: 440)
        .position(x: size.width / 2, y: crease.map { $0.bottom.midY - m.bottom / 2 }
                  ?? (wish.records.isEmpty ? size.height / 2 : max(chimeH + 60, size.height * 0.6)))
    }

    // MARK: Writing

    // On the iPhone Duo held upright the bell and paper sit above the fold (under the top bar)
    // and the chips and buttons below it.
    private var paperTop: CGFloat { m.top + 56 }

    private func paperSize(_ size: CGSize) -> CGSize {
        // the bell above the paper adds about a third of the paper's height
        let h = crease.map { min(($0.top.height - Crease.gap - paperTop) / 1.33, 360) } ?? min(size.height * 0.68, 360)
        return CGSize(width: h * 8.5 / 27.5, height: h)
    }

    private func paperCenter(_ size: CGSize) -> CGPoint {
        guard let crease else { return CGPoint(x: size.width / 2, y: size.height * 0.6) }
        let h = paperSize(size).height
        return CGPoint(x: size.width / 2, y: crease.top.maxY - Crease.gap - h / 2)
    }

    private func writing(_ size: CGSize) -> some View {
        let paper = paperSize(size)
        let c = paperCenter(size)
        let bell = paper.width * 360 / 166 / 2.5
        let chipH = min(56, size.height * 0.135)
        let btnH = min(64, size.height * 0.16)
        return ZStack {
            // bell above the paper
            Image(asset: "chime_bell_\(world.rawValue)").resizable()
                .frame(width: bell, height: bell * 1.25)
                .position(x: c.x, y: c.y - paper.height / 2 - bell * 1.25 / 2 + bell * 0.04)
            // paper
            WishPaperView(world: world, strokes: wish.strokes, active: wish.current, tip: wish.tip,
                          preset: wish.isPresetPaper, inkAlpha: wish.inkAlpha, cursor: wish.cursor, cursorPulse: wish.cursorPulse)
                .frame(width: paper.width, height: paper.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in wish.draw(CGPoint(x: v.location.x / paper.width, y: 1 - v.location.y / paper.height)) }
                    .onEnded { _ in wish.endDraw() })
                .position(c)

            // left: preset chips
            // two columns, three rows: the five presets, then "write my own"
            let ids = WishPresets.ids + [WishPresets.writeOwn]
            let chipW = chipH * 420 / 160
            VStack(spacing: chipH * 0.08) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: chipW * 0.02) {
                        chip(ids[row * 2], height: chipH)
                        chip(ids[row * 2 + 1], height: chipH)
                    }
                }
            }
            .position(chipsPoint(size, c: c, paper: paper, chipW: chipW, btnW: btnH * 420 / 202))

            // right: release above rewrite
            VStack(spacing: btnH * 0.25) {
                let w = world.rawValue, l = app.language.rawValue
                WishButton(base: "wish_btn_release_\(w)_\(l)", enabled: wish.canRelease, height: btnH) { wish.release() }
                    .modifier(ReleaseHop(trigger: wish.releasePulseAt))
                WishButton(base: "wish_btn_rewrite_\(l)", enabled: wish.canRewrite, height: btnH) { wish.rewrite() }
            }
            .position(buttonsPoint(size, c: c, paper: paper, chipW: chipW, btnH: btnH))

            let hintPoint = { let b = buttonsPoint(size, c: c, paper: paper, chipW: chipW, btnH: btnH)
                              return CGPoint(x: b.x, y: b.y + btnH * 1.65) }()
            if !wish.canRelease && wish.cursor == nil {
                Text(app.t("用手指在纸条上写字", "Write on the paper with your finger"))
                    .font(.moodium(12, .medium)).foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glass(shadow: false)
                    .frame(maxWidth: 170)
                    .position(hintPoint)
                    .allowsHitTesting(false)
            } else if wish.canRelease {
                Text(app.t("写好了？点放飞，或者把手机往上托一下", "Done? Tap Release, or lift the phone up"))
                    .font(.moodium(12, .medium)).foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glass(shadow: false)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 170)
                    .position(hintPoint)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Centre of the chip grid: left of the paper, or the left part of the half below the fold.
    private func chipsPoint(_ size: CGSize, c: CGPoint, paper: CGSize, chipW: CGFloat, btnW: CGFloat) -> CGPoint {
        guard let crease else { return CGPoint(x: c.x - paper.width / 2 - 22 - chipW, y: c.y - 6) }
        let total = chipW * 2.04 + 34 + btnW
        return CGPoint(x: size.width / 2 - total / 2 + chipW * 1.02, y: crease.bottom.minY + Crease.gap + (crease.bottom.height - Crease.gap - m.bottom) * 0.42)
    }

    /// Centre of release / rewrite: right of the paper, or right of the chips below the fold.
    private func buttonsPoint(_ size: CGSize, c: CGPoint, paper: CGSize, chipW: CGFloat, btnH: CGFloat) -> CGPoint {
        let btnW = btnH * 420 / 202
        guard crease != nil else { return CGPoint(x: c.x + paper.width / 2 + 34 + btnW / 2, y: c.y - btnH * 0.3) }
        let total = chipW * 2.04 + 34 + btnW
        let chips = chipsPoint(size, c: c, paper: paper, chipW: chipW, btnW: btnW)
        return CGPoint(x: size.width / 2 + total / 2 - btnW / 2, y: chips.y - btnH * 0.45)
    }

    private func chip(_ id: String, height: CGFloat) -> some View {
        let l = app.language.rawValue
        let selected = wish.presetId == id
        let base = "wish_chip_\(id)_\(l)"
        return Button {
            if id == WishPresets.writeOwn { wish.writeOwn() } else { wish.pickPreset(id) }
        } label: { EmptyView() }
        .buttonStyle(ChipStyle(idle: selected ? "\(base)_selected_\(world.rawValue)" : "\(base)_idle", pressed: "\(base)_pressed", height: height))
    }

    // MARK: Flight

    /// The finished paper shrinks onto a bell and flies up to its place in the row.
    private func flight(_ record: WishRecord, _ size: CGSize) -> some View {
        let s = slots(size)
        let slot = min(wish.records.count, s.count - 1)
        let paper = paperSize(size)
        let startScale = paper.width / chimeStripW
        let stripCenterBelowMiddle = chimeBellH - chimeH / 2 + chimeStripW * 27.5 / 8.5 / 2
        let start = CGPoint(x: paperCenter(size).x, y: paperCenter(size).y - stripCenterBelowMiddle * startScale)
        let end = CGPoint(x: s.x(slot), y: chimeH / 2 - 4)
        return TimelineView(.animation) { ctx in
            let u = min(1, ctx.date.timeIntervalSince(flyStart ?? ctx.date) / 1.9)
            let p = CGFloat(u * u * (3 - 2 * u))
            HangingChime(world: world, record: record, width: bellW)
                .frame(width: bellW, height: chimeH)
                .scaleEffect(startScale + (1 - startScale) * p)
                .rotationEffect(.degrees(sin(Double(p) * 14) * 6 * Double(1 - p)), anchor: .top)
                .position(x: start.x + (end.x - start.x) * p, y: start.y + (end.y - start.y) * p - CGFloat(sin(Double(p) * .pi)) * 40)
        }
        .onAppear {
            flyStart = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.95) { wish.landed(); flyStart = nil }
        }
        .allowsHitTesting(false)
    }

    private func back() {
        if wish.mode == .writing, !wish.records.isEmpty { wish.cancelWriting(); return }
        app.leaveWish()
    }
}

/// Wish button sprites: idle / pressed / disabled (rewrite has no disabled art: 45 % alpha).
private struct WishButton: View {
    let base: String
    let enabled: Bool
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) { EmptyView() }
            .buttonStyle(ChipStyle(idle: enabled ? base + "_idle" : (UIImage(named: base + "_disabled") != nil ? base + "_disabled" : base + "_idle"),
                                   pressed: base + "_pressed", height: height))
            .opacity(enabled || UIImage(named: base + "_disabled") != nil ? 1 : 0.45)
            .disabled(!enabled)
    }
}

private struct ChipStyle: ButtonStyle {
    let idle: String
    let pressed: String
    let height: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        Image(asset: configuration.isPressed && UIImage(named: pressed) != nil ? pressed : idle)
            .resizable().scaledToFit()
            .frame(height: height)
            .contentShape(Capsule().inset(by: height * 0.12))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

/// Two little hops when a preset finishes writing (WishActionButton.Pulse).
private struct ReleaseHop: ViewModifier {
    var trigger: Date?
    @State private var y: CGFloat = 0
    func body(content: Content) -> some View {
        content.offset(y: y).onChange(of: trigger) { _, _ in
            for (k, v) in [-9, 0, -5, 0].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(k) * 0.13) {
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) { y = CGFloat(v) }
                }
            }
        }
    }
}
