import SwiftUI
import SceneKit
import SpriteKit
import Combine

/// Runs the squeeze rescue (ported from MoodiRescueDirector) on the phone:
/// Moodi falls into the pillow, asks for help with a muffled voice, each squeeze of the base
/// fills the energy ring and sprays the world's props, Moodi's voice gets clearer as energy
/// rises, and at 100 % the pillow pops and Moodi jumps out.
///
/// On top of that, from the newer visionOS build:
/// - three ways to squeeze (free / rhythm / breath, SqueezeModeController), the mood check
///   picks the first one;
/// - four gifts grow next to the pillow at 20 / 50 / 80 / 100 %;
/// - poke Moodi and it giggles (Touched).
@MainActor
final class SqueezeDirector: ObservableObject {
    enum Phase { case intro, playing, complete }
    enum BreathStep: Equatable { case ready, inhale, exhale }

    /// Fireworks cues for the iPhone Duo tabletop sky; `from` is in canvas points.
    enum SkyCue {
        case squeeze(intensity: Double, from: CGPoint?)
        case gift(from: CGPoint?)
        case finale(from: CGPoint?)
    }
    let skyCues = PassthroughSubject<SkyCue, Never>()

    @Published private(set) var phase: Phase = .intro
    @Published private(set) var energy: Double = 0
    @Published private(set) var lastSqueeze = Date()
    @Published private(set) var subtitle: String?
    @Published private(set) var showHint = false
    @Published private(set) var showCard = false

    // Modes
    @Published private(set) var mode: SqueezeMode = .free
    @Published private(set) var recommendedMode: SqueezeMode?
    @Published private(set) var modeToastAt: Date?
    @Published private(set) var combo = 0
    /// The last rhythm press: how close to the beat (0 miss…1 perfect), and whether it came before the beat.
    @Published private(set) var lastHit: RhythmHit?
    @Published private(set) var rhythmAdaptive = false
    @Published private(set) var breathStep: BreathStep = .ready
    @Published private(set) var breathStepAt = Date()
    @Published private(set) var breaths = 0
    @Published private(set) var guide: String?

    // Gifts and dock
    @Published private(set) var giftsGrown = 0

    let world: MoodWorld
    let stage: SoftStage
    let sparkles: SparkleScene
    private let sensor = PressSensor()
    private let haptics = Haptics()
    private let audio = AudioDirector.shared

    private(set) var language: Language = .zh
    /// The breath hold in progress was started by a finger on the screen (not the base).
    private var touchHolding = false
    /// Right after a screen press the phone may still rock on the base; don't count that twice.
    private var touchQuietUntil: CFTimeInterval = 0
    private var mood: MoodKind?
    private var squeezes = 0
    private(set) var totalSqueezes = 0
    let visitStart = Date()
    private var acceptingSqueezes = false
    private var hasTaught = false
    private var lastEncourage = Date.distantPast
    private var lastNudge = Date.distantPast
    private var lastBounceSound: CFTimeInterval = 0
    private var pending: [DispatchWorkItem] = []
    private var voiceTimer: Timer?
    private var idleTimer: Timer?
    private var tickTimer: Timer?
    private var touchStart: Date?
    private var holdTimer: Timer?
    private var running = false
    private var introStarted = false
    private var popped = false
    private var everCompleted = false

    // Scoring
    private var params = SqueezeParameters()
    private var rhythm: RhythmScorer?
    private var breath: BreathScorer?
    private var sessionStart = CACurrentMediaTime()
    private var modeStart = CACurrentMediaTime()
    private var holdStart: Double?
    private var lastRhythmStart: Double?
    private var units: Double = 0   // energy out of 100
    /// The sensory-bag guide is open: base motion feeds its try-it meter, the story waits.
    private(set) var guiding = false
    let probe = BagProbe()
    private var baseFlow = 0.0      // base motion energy not paid yet
    private var lastFlowPay = 0.0
    private var baseDepth = 0.0     // the pillow following the base, 0…1
    /// 0…1 how hard the base is rocking right now (free mode), smoothed; read by the atmosphere
    /// layer every frame, so not published.
    private(set) var flowLevel = 0.0
    /// The pillow's screen rect, kept for the atmosphere layer.
    private(set) var jellyRect: CGRect?

    init(world: MoodWorld) {
        self.world = world
        stage = SoftStage(world: world)
        sparkles = SparkleScene(world: world)
        haptics.sensor = sensor

        stage.onEdgeHit = { [weak self] point, strength in
            guard let self else { return }
            self.sparkles.edgeSplash(at: self.sparkles.toScene(point), strength: strength)
            self.haptics.edge(strength)
            let now = CACurrentMediaTime()
            guard now - self.lastBounceSound > 0.12 else { return }
            self.lastBounceSound = now
            self.audio.sfx("sfx_bounce", volume: Float(0.06 + 0.18 * strength))
        }
        stage.onReady = { [weak self] in
            guard let self, self.running, !self.introStarted, !self.guiding else { return }
            self.runIntro()
        }
        stage.onPop = { [weak self] in self?.meshPop() }
        sensor.onPulse = { [weak self] pulse in self?.pulse(intensity: pulse.intensity, side: pulse.side) }
        sensor.onHold = { [weak self] down in self?.baseHold(down) }
        sensor.onMotion = { [weak self] gravity, _ in self?.applyMotion(gravity) }
        sensor.onLive = { [weak self] flow, depth in self?.baseLive(flow: flow, depth: depth) }
        sensor.onShake = { [weak self] in
            self?.stage.scatter()
            self?.sparkles.scatter()
        }
    }

    // MARK: - Settings

    /// Both inputs are always live: rocks of the base (gyroscope) and presses on the screen.
    func configure(language: Language, sensitivity: Sensitivity, mood: MoodKind?) {
        let firstTime = self.mood == nil && !running
        self.language = language
        sensor.sensitivity = sensitivity
        if firstTime {
            self.mood = mood
            recommendedMode = mood?.recommendedMode
            setMode(mood?.recommendedMode ?? .free, announce: false)
        }
        updateGuide()
    }

    // MARK: - Life cycle

    func start() {
        guard !running else { return }
        running = true
        #if MOODIUM_AUTOPILOT
        AutopilotHooks.director = self
        #endif
        sessionStart = CACurrentMediaTime()
        audio.playMusic(world.bgm)
        haptics.prepare()
        sensor.start()
        voiceTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let fallback = Float(0.6 + 0.4 * abs(sin(Date.timeIntervalSinceReferenceDate * 7 * 2 * .pi)))
                let level = self.audio.isSpeaking ? (self.audio.voiceLevel > 0.01 ? self.audio.voiceLevel : fallback) : 0
                self.stage.withRescue { $0.talk = level }
            }
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdle() }
        }
        // Breath mode pays while the base is held.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        after(0.6) { [weak self] in
            guard let self, self.stage.modelsReady, !self.introStarted, !self.guiding else { return }
            self.runIntro()
        }
    }

    func stop() {
        running = false
        cancelPending()
        idleTimer?.invalidate()
        voiceTimer?.invalidate()
        holdTimer?.invalidate()
        tickTimer?.invalidate()
        sensor.stop()
        audio.stopVoice()
        audio.stopBreath()
        audio.stopMusic()
        stage.withRescue { $0.reset() }
        introStarted = false
    }

    func pause() {
        sensor.stop()
        audio.pauseAll()
        sparkles.isPaused = true
        if holdStart != nil { holdEnded(interrupted: true) }
    }

    func resume() {
        guard running else { return }
        sensor.start()
        audio.resumeAll()
        sparkles.isPaused = false
    }

    // MARK: - Sensory bag guide

    /// Open the guide: until `endGuide`, base motion goes to the try-it meter (and on the first
    /// visit Moodi's fall-in waits).
    func beginGuide() {
        guiding = true
        probe.progress = 0
        probe.tilt = 0
        probe.lastMove = .distantPast
    }

    func endGuide() {
        guiding = false
        if running, stage.modelsReady, !introStarted { runIntro() }
    }

    private func feedProbe(tilt: Double? = nil, earned: Double) {
        if let tilt { probe.tilt += (tilt - probe.tilt) * 0.5 }
        guard earned > 0 else { return }
        let before = probe.progress
        probe.progress = min(1, probe.progress + earned)
        probe.lastMove = Date()
        if before < 1, probe.progress >= 1 {
            haptics.success()
            audio.sfx("sfx_chime", volume: 0.4)
        }
    }

    /// The pillow's screen rect changed (layout or rotation).
    func layoutChanged() {
        if let rect = stage.jellyScreenRect() { sparkles.setJellyRect(rect); jellyRect = rect }
        sparkles.spriteMoodi = !stage.usesMeshMoodi
        sparkles.setMouthPoint(stage.mouthScreenPoint())
    }

    var metrics: MoodVisitMetrics {
        MoodVisitMetrics(world: world, seconds: Date().timeIntervalSince(visitStart), squeezes: totalSqueezes, mode: mode,
                         completed: phase == .complete || everCompleted)
    }

    // MARK: - Story

    private func runIntro() {
        introStarted = true
        popped = false
        phase = .intro
        acceptingSqueezes = false
        showHint = false
        layoutChanged()
        audio.sfx("sfx_hop", volume: 0.5)
        let splash: () -> Void = { [weak self] in
            guard let self else { return }
            // K1 just before the splash, then the pillow swallows Moodi.
            if let point = self.stage.mouthScreenPoint() { self.sparkles.splash(at: self.sparkles.toScene(point)) }
            self.stage.withRescue { $0.setPeeking(true) }
            self.stage.kick(0.9, side: 0)
            self.audio.sfx("sfx_squish", volume: 0.6)
            self.haptics.squeeze(0.8)
            self.acceptingSqueezes = true
            self.after(0.7) { [weak self] in
                guard let self else { return }
                self.say("K2", muffled: true) { [weak self] in
                    guard let self else { return }
                    if !self.hasTaught {
                        self.hasTaught = true
                        self.say("K3", muffled: true) { [weak self] in self?.beginPlay() }
                    } else {
                        self.beginPlay()
                    }
                }
            }
        }
        if stage.usesMeshMoodi { stage.onSplash = splash; stage.rescueFallIn() }
        else { sparkles.moodiFallIn(onSplash: splash) }
        after(1.75) { [weak self] in self?.say("K1", clarity: 1, volume: 0.45) }
    }

    private func beginPlay() {
        guard phase == .intro else { return }
        phase = .playing
        lastSqueeze = Date()
        withAnimation(.easeOut(duration: 0.4)) { showHint = true }
        updateGuide()
    }

    // MARK: - Modes

    func requestMode(_ m: SqueezeMode) {
        guard m != mode else { return }
        setMode(m, announce: true)
    }

    private func setMode(_ m: SqueezeMode, announce: Bool) {
        if holdStart != nil { holdEnded(interrupted: true) }
        audio.stopBreath()
        mode = m
        sensor.holdMode = m == .breath
        // A manual switch uses the default tuning; the recommended start uses the mood's.
        params = announce ? SqueezeParameters() : SqueezeParameters.forMood(mood)
        rhythm = m == .rhythm ? RhythmScorer(params) : nil
        breath = m == .breath ? BreathScorer(params) : nil
        modeStart = CACurrentMediaTime()
        combo = 0; lastHit = nil; rhythmAdaptive = false
        breathStep = .ready; breathStepAt = Date()
        lastRhythmStart = nil
        if announce {
            audio.sfx("sfx_hop", volume: 0.35)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { modeToastAt = Date() }
            after(1.6) { [weak self] in withAnimation(.easeOut(duration: 0.3)) { self?.modeToastAt = nil } }
        }
        updateGuide()
    }

    /// Beat clock for rhythm mode (seconds since the mode started).
    func beatTime(_ now: Double = CACurrentMediaTime()) -> Double { now - modeStart }

    /// 0…1 position in the current beat (0 = on the beat), for the incoming ring.
    func rhythmPhase(_ now: Double = CACurrentMediaTime()) -> Double {
        rhythm?.phase(now: now, beatTime: beatTime(now)) ?? 0
    }

    var rhythmPeriod: Double { rhythm?.adaptive == true ? rhythm!.adaptiveInterval : params.rhythmPeriod }

    /// How long a full breath out is (5 s, 6 s when tense), for the exhale countdown.
    var exhaleSeconds: Double { params.exhaleOk }

    /// Seconds the base (or screen) has been held, for the breath tide.
    func heldSeconds(_ now: Double = CACurrentMediaTime()) -> Double { holdStart.map { now - $0 } ?? 0 }

    // MARK: - Input

    /// Sensor pulse: one squeeze of the base.
    private func pulse(intensity: Double, side: Double) {
        if guiding {
            haptics.squeeze(0.3 + 0.3 * intensity)
            audio.sfx("sfx_squish", volume: 0.2)
            feedProbe(earned: 0.12)
            return
        }
        // a finger on the screen also rocks the phone on the base: that press already counts
        guard touchStart == nil, CACurrentMediaTime() >= touchQuietUntil else { return }
        switch mode {
        case .free:
            // the base already fills the bar continuously (`baseLive`); a counted squeeze adds a little more
            guard acceptingSqueezes, phase != .complete else { return }
            squeezeEffects(intensity: intensity, side: side)
            pay(units: 1.2 + 1.5 * intensity)
        case .rhythm: rhythmHit(intensity: intensity, side: side)
        case .breath:
            // the hold detector drives breathing; a quick tap still nudges the pillow
            if holdStart == nil { stage.kick(intensity * 0.5, side: side) }
        }
    }

    /// Continuous base input, like a spirit level: the pillow sinks as far as the phone is tipped,
    /// and in free mode every bit of rocking adds energy, with no threshold to reach first.
    private func baseLive(flow: Double, depth: Double) {
        if guiding { feedProbe(tilt: depth, earned: flow / 8); return }
        let depth = abs(depth)
        let now = CACurrentMediaTime()
        let free = touchStart == nil && holdStart == nil && now >= touchQuietUntil
        if mode != .breath, free {
            // ease toward the tilt so sensor jitter doesn't shimmer the pillow
            baseDepth += (depth - baseDepth) * 0.5
            stage.setHold(baseDepth * 0.85)
        } else {
            baseDepth = 0
        }
        // how hard the bag is rocking: flow is energy units for ~1/60 s, ~8 units/s is a good steady rock
        let level = mode == .free && free && acceptingSqueezes && phase != .complete ? min(1, flow * 60 / 8) : 0
        flowLevel += (level - flowLevel) * (level > flowLevel ? 0.25 : 0.04)
        sparkles.setFlow(flowLevel)
        guard mode == .free, free else { baseFlow = 0; return }
        baseFlow += flow
        if baseFlow >= 0.5 || (baseFlow > 0 && now - lastFlowPay > 0.15) {
            lastFlowPay = now
            if phase == .intro, acceptingSqueezes { phase = .playing }
            pay(units: baseFlow, effects: false)
            // rocking counts as playing: the ring stays awake and Moodi doesn't ask if you're still there
            if baseFlow > 0.05, Date().timeIntervalSince(lastSqueeze) > 1 { lastSqueeze = Date() }
            baseFlow = 0
        }
    }

    /// Sensor hold: the base is down / let go.
    private func baseHold(_ down: Bool) {
        guard mode == .breath, !touchHolding else { return }
        if down {
            guard touchStart == nil, CACurrentMediaTime() >= touchQuietUntil else { return }
            holdBegan(side: 0)
        } else {
            holdEnded(interrupted: false)
        }
    }

    /// Free mode squeeze (also what the autopilot and touch mode call).
    func squeeze(intensity: Double, side: Double) {
        guard acceptingSqueezes, phase != .complete else { return }
        if mode == .rhythm { rhythmHit(intensity: intensity, side: side); return }
        squeezeEffects(intensity: intensity, side: side)
        pay(units: 2.4 + 3 * intensity)
    }

    private func rhythmHit(intensity: Double, side: Double) {
        guard acceptingSqueezes, phase != .complete, let rhythm else { return }
        let now = CACurrentMediaTime()
        let gap = lastRhythmStart.map { now - $0 } ?? .infinity
        lastRhythmStart = now
        // past the middle of the beat, the press came before the next beat
        let early = rhythmPhase(now) > 0.5
        let earned = rhythm.started(now: now, beatTime: beatTime(now), strong: intensity >= 0.6)
        combo = rhythm.combo
        rhythmAdaptive = rhythm.adaptive
        lastHit = RhythmHit(at: Date(), accuracy: rhythm.lastAccuracy, early: early)
        squeezeEffects(intensity: max(intensity, 0.4 + 0.6 * rhythm.lastAccuracy), side: side)
        if rhythm.lastAccuracy > 0 {
            audio.sfx("sfx_rhythm_hit", volume: Float(0.18 + 0.2 * rhythm.lastAccuracy))
            // a streak plays a little tune: the world's three chime notes, rising
            audio.sfx("chime_ring_\(world.rawValue)_\((combo - 1) % 3)", volume: Float(0.12 + 0.18 * rhythm.lastAccuracy))
            if rhythm.lastRush { sparkles.giftBurst(at: nil); haptics.gift() }
        }
        pay(units: earned)
        guide = rhythmGuide(spam: gap < params.spamSoft)
    }

    private func holdBegan(side: Double) {
        guard acceptingSqueezes, phase != .complete, holdStart == nil, let breath else { return }
        let now = CACurrentMediaTime()
        holdStart = now
        squeezes += 1; totalSqueezes += 1
        lastSqueeze = Date()
        stage.kick(0.35, side: side)
        stage.withRescue { $0.setHeld(true) }
        haptics.squeeze(0.35)
        audio.sfx("sfx_squish", volume: 0.25)
        audio.breath("breath_inhale")
        withAnimation(.easeInOut(duration: 0.3)) { breathStep = .inhale; breathStepAt = Date() }
        pay(units: breath.started(now: now))
        updateGuide()
        if squeezes >= 2, showHint { withAnimation(.easeOut(duration: 0.5)) { showHint = false } }
    }

    private func holdEnded(interrupted: Bool) {
        guard let start = holdStart, let breath else { holdStart = nil; return }
        let now = CACurrentMediaTime()
        holdStart = nil
        stage.setHold(0)
        stage.withRescue { $0.setHeld(false) }
        let held = now - start
        let earned = breath.released(now: now, held: held)
        if interrupted { audio.stopBreath(); breathStep = .ready; return }
        audio.breath("breath_exhale")
        breaths = breath.breaths
        withAnimation(.easeInOut(duration: 0.3)) { breathStep = .exhale; breathStepAt = Date() }
        // The exhale sprays the props: a good breath, a big spray.
        let q = breath.lastQuality
        stage.burst(0.3 + 0.7 * q, side: 0)
        sparkles.burst(intensity: 0.3 + 0.7 * q, side: 0)
        if q > 0.6 { haptics.squeeze(0.6) }
        guide = q > 0 ? nil : text("longer")
        pay(units: earned)
        after(params.exhaleOk) { [weak self] in
            guard let self, self.breathStep == .exhale, self.holdStart == nil else { return }
            withAnimation(.easeInOut(duration: 0.4)) { self.breathStep = .ready; self.breathStepAt = Date() }
            self.updateGuide()
        }
    }

    private func tick() {
        guard let start = holdStart, let breath else { return }
        let held = CACurrentMediaTime() - start
        // pillow sinks slowly while breathing in
        stage.setHold(min(1, held / params.inhale) * 0.8)
        pay(units: breath.held(seconds: held, dt: 0.1), effects: false)
    }

    /// The visual / haptic / sound side of one squeeze.
    private func squeezeEffects(intensity: Double, side: Double) {
        if phase == .intro { phase = .playing }
        squeezes += 1; totalSqueezes += 1
        lastSqueeze = Date()
        stage.kick(intensity, side: side)
        stage.burst(intensity, side: side)
        sparkles.burst(intensity: intensity, side: side)
        skyCues.send(.squeeze(intensity: intensity, from: stage.mouthScreenPoint()))
        haptics.squeeze(intensity)
        audio.sfx("sfx_squish", volume: Float(0.25 + 0.35 * intensity))
        if stage.usesMeshMoodi {
            stage.withRescue { $0.squeeze(intensity: Float(intensity)) }
        }
        if squeezes >= 3, showHint, mode == .free { withAnimation(.easeOut(duration: 0.5)) { showHint = false } }
    }

    /// Adds energy (out of 100) and runs the story beats it crosses.
    private func pay(units earned: Double, effects: Bool = true) {
        guard earned > 0, phase != .complete, acceptingSqueezes else { return }
        let assisted = earned * energyAssist(elapsed: CACurrentMediaTime() - sessionStart, mode: mode)
        let before = energy
        units = min(100, units + assisted)
        energy = units / 100
        sparkles.setEnergy(energy)
        if stage.usesMeshMoodi {
            stage.withRescue {
                $0.setProgress(Float(energy))
                if effects, [1, 5, 10, 15].contains(squeezes) { $0.blink(delay: 0.1) }
                if before < 0.2 && energy >= 0.2 { $0.blink(count: 2, delay: 0.15) }
            }
        } else if effects { sparkles.moodiReact(energy: energy, intensity: 0.6) }

        for (i, stageAt) in Gift.stages.enumerated() where before < stageAt && energy >= stageAt {
            growGift(i)
        }
        let lines: [(Double, String)] = [(0.2, "K5"), (0.5, "K6"), (0.8, "K7")]
        if energy >= 1 {
            complete()
        } else if let line = lines.first(where: { before < $0.0 && energy >= $0.0 }) {
            haptics.gift()
            audio.sfx("sfx_chime", volume: 0.55)
            say(line.1)
        } else if effects, squeezes == 1 {
            say("K4")
        } else if effects, squeezes > 4, Date().timeIntervalSince(lastEncourage) > 18, !audio.isSpeaking, Double.random(in: 0...1) < 0.3 {
            lastEncourage = Date()
            say(["K8a", "K8b", "K8c"].randomElement()!)
        }
    }

    #if MOODIUM_AUTOPILOT
    func autopilotHold(_ down: Bool) { if down { holdBegan(side: 0) } else { holdEnded(interrupted: false) } }
    /// Fakes the bag rocking at `level` (0…1) for one 1/60 s sample.
    func autopilotRock(_ level: Double, t: Double) { baseLive(flow: level * 8 / 60, depth: 0.5 * sin(t * 9)) }
    func autopilotBeatDelay() -> Double { let u = rhythmPhase(); return (1 - u) * rhythmPeriod }
    #endif

    // MARK: - Gifts

    private func growGift(_ i: Int) {
        guard stage.garden.grow(i) else { return }
        giftsGrown = stage.garden.grown.count
        audio.sfx(world == .candy ? "grow_candy" : "grow_nature", volume: 0.55)
        let p = stage.screenPoint(stage.garden.center(i))
        if let p { sparkles.giftBurst(at: p) }
        skyCues.send(.gift(from: p))
    }

    // MARK: - Completion

    private func complete() {
        phase = .complete
        everCompleted = true
        acceptingSqueezes = false
        if holdStart != nil { holdEnded(interrupted: true) }
        withAnimation { showHint = false; guide = nil }
        haptics.success()
        if stage.usesMeshMoodi {
            after(1.2) { [weak self] in self?.stage.withRescue { $0.forcePop() } }
            return
        }
        stage.popJelly()
        after(0.55) { [weak self] in
            guard let self else { return }
            self.sparkles.moodiPopOut()
            self.sparkles.celebrate()
            self.skyCues.send(.finale(from: self.stage.mouthScreenPoint()))
            self.audio.sfx("sfx_complete", volume: 0.7)
            self.stage.rain(duration: 2.6)
        }
        after(1.1) { [weak self] in self?.say("K10", clarity: 1) }
        after(3.6) { [weak self] in withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { self?.showCard = true } }
    }

    private func meshPop() {
        guard running, phase == .complete, !popped else { return }
        popped = true
        stage.burst(1, side: 0); stage.burst(1, side: 0)
        sparkles.celebrate(); audio.sfx("sfx_complete", volume: 0.7); stage.rain(duration: 2.6)
        skyCues.send(.finale(from: stage.mouthScreenPoint()))
        after(0.55) { [weak self] in self?.say("K10", clarity: 1) }
        after(3.05) { [weak self] in withAnimation { self?.showCard = true } }
    }

    /// Close the "Moodi is free" card and stay to play.
    func dismissCard() {
        withAnimation(.easeOut(duration: 0.25)) { showCard = false }
    }

    func replay() {
        flowLevel = 0
        withAnimation(.easeOut(duration: 0.25)) { showCard = false }
        cancelPending()
        audio.stopVoice()
        energy = 0; units = 0
        squeezes = 0
        giftsGrown = 0
        sparkles.setEnergy(0)
        sparkles.moodiLeave()
        stage.clearProps()
        stage.garden.clear()
        setMode(mode, announce: false)
        sessionStart = CACurrentMediaTime()
        if stage.usesMeshMoodi { stage.withRescue { $0.leave() } } else { stage.regrowJelly() }
        after(0.7) { [weak self] in self?.runIntro() }
    }

    // MARK: - Moodi poke

    /// A tap on the screen: if it lands on Moodi, Moodi giggles.
    func tap(at point: CGPoint) {
        if stage.usesMeshMoodi {
            guard stage.hitsMoodi(point) else { return }
            var ok = false
            stage.withRescue { ok = $0.touch() }
            guard ok else { return }
            sparkles.pokeSparkle(at: point)
        } else {
            guard sparkles.spriteMoodiHit(point) else { return }
            sparkles.moodiPoke()
        }
        haptics.squeeze(0.3)
        audio.sfx("sfx_hop", volume: 0.45)
        if phase == .complete, !audio.isSpeaking, Double.random(in: 0...1) < 0.5 {
            say(["K8a", "K8b"].randomElement()!, clarity: 1)
        }
    }

    // MARK: - Idle

    private func checkIdle() {
        // a pause is fine: only a soft call after a long quiet, at most every 1.5 min, never in breath mode
        guard phase == .playing, energy > 0, energy < 1, holdStart == nil, mode != .breath else { return }
        let now = Date()
        if now.timeIntervalSince(lastSqueeze) > 25, now.timeIntervalSince(lastNudge) > 90, !audio.isSpeaking {
            lastNudge = now
            say("K9")
        }
    }

    // MARK: - Touch (always on, alongside the base)

    func touchBegan() {
        guard touchStart == nil, acceptingSqueezes else { return }
        touchStart = Date()
        switch mode {
        case .breath:
            // if the base is already held, the finger just joins that breath
            if holdStart == nil { holdBegan(side: 0); touchHolding = holdStart != nil }
        case .rhythm:
            rhythmHit(intensity: 0.6, side: 0)
        case .free:
            stage.withRescue { $0.setHeld(true) }
            holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let start = self.touchStart else { return }
                    self.stage.setHold(min(1, Date().timeIntervalSince(start) / 0.6))
                }
            }
        }
    }

    func touchEnded(atX x: CGFloat, width: CGFloat) {
        guard let start = touchStart else { return }
        touchStart = nil
        touchQuietUntil = CACurrentMediaTime() + 0.35
        holdTimer?.invalidate()
        switch mode {
        case .breath:
            if touchHolding { touchHolding = false; holdEnded(interrupted: false) }
        case .rhythm: break
        case .free:
            stage.setHold(0)
            stage.withRescue { $0.setHeld(false) }
            let held = min(1, Date().timeIntervalSince(start) / 0.6)
            let side = width > 0 ? Double((x / width - 0.5) * 2) : 0
            squeeze(intensity: 0.35 + 0.65 * held, side: max(-1, min(1, side)))
        }
    }

    // MARK: - Guide lines

    private func text(_ key: String) -> String {
        let thing = language == .zh ? "感官袋或屏幕" : "the bag or the screen"
        switch key {
        case "ready": return language == .zh ? "准备好了，就按住\(thing)" : "Press and hold \(thing) when you're ready"
        case "hold": return language == .zh ? "按住\(thing)，慢慢吸气" : "Hold \(thing), breathe in slowly"
        case "longer": return language == .zh ? "可以按久一点，跟着光慢慢吸气" : "Hold a little longer, follow the light"
        case "rhythm": return language == .zh ? "光圈碰到圆环时，按一下\(thing)" : "Squeeze when the light reaches the ring"
        case "follow": return language == .zh ? "节拍开始跟着你的节奏走了" : "The beat now follows you"
        case "slow":
            return world == .candy ? (language == .zh ? "慢一点，跟着光圈，糖果会更多" : "A little slower — follow the ring for more candy")
                                   : (language == .zh ? "慢一点，跟着光圈，花会开得更多" : "A little slower — follow the ring for more flowers")
        default: return ""
        }
    }

    private func rhythmGuide(spam: Bool) -> String? {
        if spam { return text("slow") }
        if rhythmAdaptive { return text("follow") }
        return combo >= 3 ? nil : text("rhythm")
    }

    private func updateGuide() {
        guard phase != .complete else { guide = nil; return }
        switch mode {
        case .free: guide = nil
        case .rhythm: guide = rhythmGuide(spam: false)
        case .breath:
            switch breathStep {
            case .ready: guide = text("ready")
            case .inhale: guide = breaths == 0 ? text("hold") : nil
            case .exhale: guide = nil
            }
        }
    }

    // MARK: - Motion

    private func applyMotion(_ g: SIMD2<Double>) {
        // Flat on the base, gravity sits mostly behind the screen; keep a gentle "down" then,
        // and let real tilt take over as the phone rocks or stands up.
        let len = (g.x * g.x + g.y * g.y).squareRoot()
        let mixed = SIMD2(g.x * 1.3, g.y * 1.3 - max(0, 0.75 - len))
        stage.setGravity(mixed)
        stage.setParallax(g)
        sparkles.setGravity(CGVector(dx: mixed.x, dy: mixed.y))
    }

    // MARK: - Voice

    private func say(_ id: String, muffled: Bool = false, clarity: Double? = nil, volume: Float = 1, completion: (() -> Void)? = nil) {
        let lang = language.rawValue
        let file = muffled ? "moodi_vo_\(id)_\(lang)_muffled" : "moodi_vo_\(id)_\(lang)"
        let c = clarity ?? (muffled ? 1 : 0.15 + 0.85 * energy)
        let duration = audio.voice(file, clarity: c, volume: volume, completion: completion)
        stage.withRescue { $0.talk = audio.isSpeaking ? max(0.6, audio.voiceLevel) : 0 }
        let text = VoiceLines.text(id, language)
        withAnimation(.easeOut(duration: 0.2)) { subtitle = text }
        after(max(1.4, duration + 0.5)) { [weak self] in
            guard let self, self.subtitle == text else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.subtitle = nil }
        }
    }

    // MARK: - Scheduling

    private func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        pending.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func cancelPending() {
        pending.forEach { $0.cancel() }
        pending.removeAll()
    }
}

struct RhythmHit: Equatable {
    var at: Date
    var accuracy: Double
    var early: Bool

    enum Grade { case perfect, good, early, late }
    var grade: Grade { accuracy >= 0.7 ? .perfect : accuracy > 0 ? .good : early ? .early : .late }
}

/// Moodi's lines from moodi_rescue_voice_lines.csv and the sticker invitations.
enum VoiceLines {
    static let lines: [String: (String, String)] = [
        "K1": ("哇啊——！", "Whoaaa—!"),
        "K2": ("哎呀，我掉进去出不来了！", "Oops — I fell in and I'm stuck!"),
        "K3": ("按一按感官袋，把我挤出来好不好？", "Can you press the sensory bag and squeeze me out?"),
        "K4": ("嘿咻！有用有用！", "Hey! It's working!"),
        "K5": ("我看到光了！", "I can see the light!"),
        "K6": ("一半啦，加油！", "Halfway there — keep going!"),
        "K7": ("就差一点点啦！", "Just a little more!"),
        "K8a": ("好舒服～", "Ooh, that feels nice!"),
        "K8b": ("再来再来！", "Again, again!"),
        "K8c": ("你好厉害！", "You're so good at this!"),
        "K9": ("还在吗？再按按我呀～", "Still there? Give me another squeeze!"),
        "K10": ("我出来啦！谢谢你救了我！", "I'm out! Thank you for saving me!"),
        "S1c": ("来糖果世界玩吧，甜甜的哦～", "Come play in Candy World — it's sweet!"),
        "S1n": ("来自然世界，一起听听风吧～", "Come to Nature World — let's listen to the wind!"),
        "S2": ("今天的你，会喜欢这里哦～", "I think you'll love it here today!"),
        "B3": ("要不要写下一件想放下的事，或者一个小心愿？", "Would you like to write down something you want to let go of, or a little wish?"),
        "B5": ("写好了吗？把它托起来，轻轻放飞吧。", "All done? Hold it up, and gently let it go."),
        "B6": ("它会替你在这里保管。", "It will keep it safe for you, right here."),
        "B7": ("你的风铃还在这里等你呢。", "Your wind chimes are still here, waiting for you."),
        "B8": ("没关系，重新写就好。", "That's okay, just write it again."),
    ]

    static func text(_ id: String, _ language: Language) -> String {
        guard let pair = lines[id] else { return "" }
        return language == .zh ? pair.0 : pair.1
    }
}
