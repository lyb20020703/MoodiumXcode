import SwiftUI
import CoreMotion
import AVFoundation

/// The wish chimes (WishChime / WishChimeGarden / WishPresetPanel) on the phone.
///
/// - Garden: your hung wishes for this world sway in a row along the top. Tilt the phone and
///   they swing (and ring when they swing hard), tap one to ring it, shake to ring them all.
/// - Writing: write on the paper strip with a finger, or pick one of five preset wishes that
///   writes itself stroke by stroke. Release (button, or lift the phone up) and the paper
///   flies up and hangs as a new chime. Rewrite (button, or shake) wipes the paper.
@MainActor
final class WishController: ObservableObject {
    enum Mode: Equatable { case garden, writing, flying }

    @Published private(set) var mode: Mode = .garden
    @Published private(set) var records: [WishRecord] = []
    @Published private(set) var strokes: [WishStroke] = []
    @Published private(set) var current: WishStroke?
    @Published private(set) var tip: CGPoint?
    @Published private(set) var inkAlpha: Double = 1
    @Published private(set) var presetId: String?
    @Published private(set) var presetWriting = false
    @Published private(set) var cursor: CGPoint?
    @Published private(set) var cursorPulse: Double = 0
    @Published private(set) var subtitle: String?
    @Published private(set) var releasePulseAt: Date?
    @Published private(set) var flying: WishRecord?
    @Published var angles: [Double] = []

    let world: MoodWorld
    private(set) var language: Language = .zh
    private var total = 0
    private var lastStrokeEnd = Date.distantPast
    private var lastAction = Date()
    private var erasing = false
    private var saving = false
    private var timeline: WishTimeline?
    private var presetStart = Date()
    private var presetDone = 0
    private var inviteUntil: Date?
    private var saidB5 = false, saidB8 = false
    private var writeLoop: AVAudioPlayer?
    private var lastPoint: (CGPoint, Date)?

    // swing
    private var omegas: [Double] = []
    private var lastRing: [Date] = []
    private var tilt = 0.0
    private var timer: Timer?
    private let motion = CMMotionManager()
    private var lastShake = Date.distantPast
    private var lastLift = Date.distantPast
    private var orientation: UIInterfaceOrientation = .landscapeRight

    init(world: MoodWorld) {
        self.world = world
        records = WishStore.load().filter { $0.world == world.rawValue }
    }

    var hasInk: Bool { WishStore.canRelease(strokes) }
    var canRelease: Bool { hasInk || presetWriting }
    var canRewrite: Bool { hasInk || current != nil || presetWriting }
    /// No button while a stroke is going, just after one, while wiping or saving.
    private var blocked: Bool { current != nil || Date().timeIntervalSince(lastStrokeEnd) < 0.35 || erasing || saving }

    // MARK: - Life cycle

    func start(language: Language) {
        self.language = language
        #if MOODIUM_AUTOPILOT
        AutopilotHooks.wish = self
        #endif
        syncSwing()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        startMotion()
        if records.isEmpty {
            beginWriting()
            say("B3")
        } else {
            say("B7")
        }
    }

    func stop() {
        timer?.invalidate()
        motion.stopDeviceMotionUpdates()
        writeLoop?.stop()
        AudioDirector.shared.stopVoice()
    }

    // MARK: - Garden

    /// The newest wishes that fit along the top.
    func visible(count: Int) -> [WishRecord] { Array(records.suffix(max(0, count))) }

    func tapChime(_ index: Int) {
        guard index < omegas.count else { return }
        omegas[index] += Double.random(in: 2.6...3.4) * (Bool.random() ? 1 : -1)
        ring(index, volume: 0.6)
    }

    private func ring(_ index: Int, volume: Float) {
        if index >= 0, index < lastRing.count { lastRing[index] = Date() }
        AudioDirector.shared.sfx("chime_ring_\(world.rawValue)_\(Int.random(in: 0...2))", volume: volume)
    }

    func ringAll() {
        for i in omegas.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.09) { [weak self] in
                guard let self, i < self.omegas.count else { return }
                self.omegas[i] += Double.random(in: 2...3.2) * (Bool.random() ? 1 : -1)
                if i % 2 == 0 { self.ring(i, volume: 0.45) }
            }
        }
    }

    private func syncSwing() {
        while angles.count < records.count { angles.append(0); omegas.append(Double.random(in: -0.2...0.2)); lastRing.append(.distantPast) }
        while angles.count > records.count { angles.removeLast(); omegas.removeLast(); lastRing.removeLast() }
    }

    // MARK: - Writing

    func beginWriting() {
        guard mode != .writing else { return }
        strokes = []; current = nil; tip = nil; total = 0; presetId = nil; timeline = nil; presetWriting = false
        inkAlpha = 1; saidB5 = false
        lastAction = Date()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { mode = .writing }
        AudioDirector.shared.sfx(world == .candy ? "grow_candy" : "grow_nature", volume: 0.4)
        _ = WishPresets.document   // parse now, not on the first chip tap
    }

    func cancelWriting() {
        finishStroke()
        writeLoop?.stop()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { mode = .garden }
    }

    /// Finger on the paper at `uv` (v = 1 at the top).
    func draw(_ uv: CGPoint) {
        guard mode == .writing, !erasing, !saving, timeline == nil, total < WishStore.maxPoints else { return }
        let p = CGPoint(x: min(1, max(0, uv.x)), y: min(1, max(0, uv.y)))
        inviteUntil = nil
        cursor = p
        if current == nil { current = [] }
        var s = current!
        if WishStore.addPoint(&s, p) {
            total += 1
            lastAction = Date()
        }
        current = s
        tip = p
        if s.count >= WishStore.maxStrokePoints {
            // long strokes are split so each mesh stays small (WishChime: 74 points)
            let last = s.last!
            finishStroke()
            current = [last]; total += 1
        }
        // pen scratch, louder with speed
        let now = Date()
        if let (q, t) = lastPoint {
            let speed = Double(hypot((p.x - q.x) * 0.085, (p.y - q.y) * 0.275)) / max(0.001, now.timeIntervalSince(t))
            setWriteVolume(Float(min(0.35, speed * 2)))
        }
        lastPoint = (p, now)
    }

    func endDraw() {
        finishStroke()
        cursor = nil
        lastPoint = nil
        setWriteVolume(0)
    }

    private func finishStroke() {
        guard var s = current else { return }
        if let t = tip, let last = s.last, s.count < 75, total < WishStore.maxPoints,
           hypot(CGFloat(last[0]) - t.x, CGFloat(last[1]) - t.y) > 0.002 {
            s.append([Float(t.x), Float(t.y)]); total += 1
        }
        if s.count >= 2 { strokes.append(s) } else { total -= s.count }
        current = nil; tip = nil
        lastStrokeEnd = Date()
    }

    func rewrite() {
        guard mode == .writing, !erasing, !saving else { return }
        finishStroke()
        stopPreset()
        presetId = nil
        if !saidB8 { saidB8 = true; say("B8") }
        erase(seconds: 0.5)
    }

    private func erase(seconds: Double, then: (() -> Void)? = nil) {
        erasing = true
        withAnimation(.easeIn(duration: seconds)) { inkAlpha = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            self.strokes = []; self.total = 0; self.current = nil; self.tip = nil
            self.inkAlpha = 1
            self.erasing = false
            self.lastAction = Date()
            then?()
        }
    }

    // MARK: Presets

    func pickPreset(_ id: String) {
        guard mode == .writing, !erasing, !saving else { return }
        // re-tapping the chosen wish keeps a signature written under it
        if presetId == id && (timeline != nil || hasInk) { return }
        guard let p = WishPresets.find(id, language) else { return }
        let hadInk = hasInk || total > 0 || presetWriting
        finishStroke()
        stopPreset()
        presetId = id
        AudioDirector.shared.sfx("sfx_hop", volume: 0.3)
        if hadInk { erase(seconds: 0.3) { [weak self] in self?.startPreset(p) } } else { startPreset(p) }
    }

    private func startPreset(_ p: WishPreset) {
        guard mode == .writing, presetId == p.id else { return }
        strokes = []; total = 0; current = nil; tip = nil
        timeline = WishTimeline(strokes: p.strokes, kinds: p.kinds)
        presetStart = Date(); presetDone = 0
        presetWriting = true
    }

    private func stepPreset() {
        guard let tl = timeline, let id = presetId, let p = WishPresets.find(id, language) else { return }
        let t = Float(Date().timeIntervalSince(presetStart))
        let f = tl.sample(t)
        if f.done != presetDone { presetDone = f.done; strokes = Array(p.strokes.prefix(f.done)) }
        if let partial = f.partial, let tp = f.tip {
            current = partial; tip = tp; cursor = tp; cursorPulse = 0.5
            setWriteVolume(0.22)
        } else {
            current = nil; tip = nil
            setWriteVolume(0)
        }
        lastAction = Date()
        if t >= tl.total { completePreset(announce: true) }
    }

    private func completePreset(announce: Bool) {
        guard timeline != nil, let id = presetId, let p = WishPresets.find(id, language) else { return }
        strokes = p.strokes
        total = p.strokes.reduce(0) { $0 + $1.count }
        stopPreset()
        lastAction = Date()
        if announce {
            ring(-1, volume: 0.5)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { releasePulseAt = Date() }
        }
    }

    private func stopPreset() {
        timeline = nil
        presetWriting = false
        current = nil; tip = nil; cursor = nil
        setWriteVolume(0)
    }

    /// "Write my own": clears a preset paper (and anything signed under it); plain handwriting stays.
    func writeOwn() {
        guard mode == .writing, !erasing, !saving else { return }
        let hadPreset = presetId != nil || timeline != nil
        stopPreset()
        presetId = nil
        if hadPreset { erase(seconds: 0.3) }
        AudioDirector.shared.sfx("sfx_hop", volume: 0.3)
        inviteUntil = Date().addingTimeInterval(1.2)
    }

    var isPresetPaper: Bool { presetId != nil }

    // MARK: Release

    func release() {
        guard mode == .writing, !erasing, !saving else { return }
        if timeline != nil { completePreset(announce: false) }
        finishStroke()
        guard hasInk else { return }
        let record = WishRecord(id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
                                world: world.rawValue,
                                createdAt: ISO8601DateFormatter().string(from: Date()),
                                strokes: strokes, preset: presetId)
        saving = true
        writeLoop?.stop()
        let ok = WishStore.append(record)
        saving = false
        guard ok else { return }
        AudioDirector.shared.sfx("chime_release", volume: 0.7)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        flying = record
        mode = .flying
    }

    /// Called by the view when the flight animation lands.
    func landed() {
        guard let record = flying else { return }
        records.append(record)
        syncSwing()
        flying = nil
        strokes = []; presetId = nil; total = 0
        withAnimation(.easeOut(duration: 0.3)) { mode = .garden }
        if let i = records.indices.last {
            omegas[i] = 2.2
            ring(i, volume: 0.7)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.say("B6") }
    }

    // MARK: - Per frame

    private func step() {
        let dt = 1.0 / 60
        let now = Date()
        // swing: underdamped pendulum toward the phone's tilt plus a little breeze
        let t = now.timeIntervalSinceReferenceDate
        for i in angles.indices {
            let target = tilt * 0.55 + 0.035 * sin(t * 2 * .pi / 2.4 + Double(i) * 0.9)
            omegas[i] += (-16 * (angles[i] - target) - 1.4 * omegas[i]) * dt
            angles[i] += omegas[i] * dt
            angles[i] = max(-0.9, min(0.9, angles[i]))
            if abs(omegas[i]) > 1.6, now.timeIntervalSince(lastRing[i]) > 1.4 { ring(i, volume: Float(min(0.55, abs(omegas[i]) * 0.15))) }
        }
        guard mode == .writing else { return }
        if timeline != nil { stepPreset() }
        if let until = inviteUntil {
            if now < until, current == nil {
                cursor = CGPoint(x: 0.5, y: 0.5)
                cursorPulse = abs(sin(until.timeIntervalSince(now) / 0.6 * .pi))
            } else { inviteUntil = nil; if current == nil { cursor = nil } }
        }
        if hasInk, !saidB5, current == nil, timeline == nil, now.timeIntervalSince(lastAction) >= 3 {
            saidB5 = true
            say("B5")
        }
    }

    // MARK: - Motion: tilt sways, shake rings / rewrites, lifting the phone releases

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        if let o = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first?.effectiveGeometry.interfaceOrientation { orientation = o }
        motion.deviceMotionUpdateInterval = 1.0 / 60
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            MainActor.assumeIsolated { self.process(m) }
        }
    }

    private func process(_ m: CMDeviceMotion) {
        let right: SIMD3<Double> = orientation == .landscapeLeft ? [0, 1, 0] : orientation == .landscapeRight ? [0, -1, 0] : [1, 0, 0]
        let g = SIMD3(m.gravity.x, m.gravity.y, m.gravity.z)
        let a = SIMD3(m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z)
        tilt += (simd_dot(g, right) - tilt) * 0.2
        let now = Date()
        let mag = simd_length(a)
        if mag > 1.3, now.timeIntervalSince(lastShake) > 1 {
            lastShake = now
            if mode == .writing, canRewrite, timeline == nil { rewrite() } else if mode == .garden { ringAll() }
            return
        }
        // lifting: acceleration against gravity, little sideways, not right after a shake
        let up = -simd_dot(a, g)
        if mode == .writing, up > 0.55, mag - abs(up) < 0.35, now.timeIntervalSince(lastShake) > 1.2,
           now.timeIntervalSince(lastLift) > 2, current == nil, canRelease {
            lastLift = now
            release()
        }
    }

    // MARK: - Sound and voice

    private func setWriteVolume(_ v: Float) {
        if writeLoop == nil, let url = Res.url("chime_write_loop", "wav") {
            writeLoop = try? AVAudioPlayer(contentsOf: url)
            writeLoop?.numberOfLoops = -1
            writeLoop?.volume = 0
        }
        guard let loop = writeLoop else { return }
        if v > 0.01, !AudioDirector.shared.muted {
            if !loop.isPlaying { loop.play() }
            loop.volume = v
        } else if loop.isPlaying {
            loop.volume = 0
        }
    }

    func say(_ id: String) {
        let duration = AudioDirector.shared.voice("moodi_vo_\(id)_\(language.rawValue)", clarity: 1)
        let text = VoiceLines.text(id, language)
        withAnimation(.easeOut(duration: 0.2)) { subtitle = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1.6, duration + 0.6)) { [weak self] in
            guard let self, self.subtitle == text else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.subtitle = nil }
        }
    }
}
