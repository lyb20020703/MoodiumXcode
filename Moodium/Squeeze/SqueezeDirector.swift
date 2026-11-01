import SwiftUI
import SceneKit
import SpriteKit

/// Runs the squeeze rescue (ported from MoodiRescueDirector) on the phone:
/// Moodi falls into the pillow, asks for help with a muffled voice, each squeeze of the base
/// fills the energy ring and sprays the world's props, Moodi's voice gets clearer as energy
/// rises, and at 100 % the pillow pops and Moodi jumps out.
///
/// On top of that, from the newer visionOS build:
/// - three ways to squeeze (free / rhythm / breath, SqueezeModeController), the mood check
///   picks the first one;
/// - four gifts grow next to the pillow at 20 / 50 / 80 / 100 %;
/// - a Candy Shower / Meadow Shower button once the energy is full, and an exit button;
/// - poke Moodi and it giggles (Touched).
@MainActor
final class SqueezeDirector: ObservableObject {
    enum Phase { case intro, playing, complete }
    enum BreathStep: Equatable { case ready, inhale, exhale }

    @Published private(set) var phase: Phase = .intro
    @Published private(set) var energy: Double = 0
    @Published private(set) var lastSqueeze = Date()
    @Published private(set) var subtitle: String?
    @Published private(set) var showHint = false
    @Published private(set) var showCard = false
    @Published private(set) var touchMode = false
    @Published private(set) var sensorMissing = false

    // Modes
    @Published private(set) var mode: SqueezeMode = .free
    @Published private(set) var recommendedMode: SqueezeMode?
    @Published private(set) var modeToastAt: Date?
    @Published private(set) var combo = 0
    @Published private(set) var lastHit: (at: Date, accuracy: Double)?
    @Published private(set) var rhythmAdaptive = false
    @Published private(set) var breathStep: BreathStep = .ready
    @Published private(set) var breathStepAt = Date()
    @Published private(set) var breaths = 0
    @Published private(set) var guide: String?

    // Gifts and dock
    @Published private(set) var giftToast: (index: Int, name: String)?
    @Published private(set) var giftsGrown = 0
    @Published private(set) var showering = false
    @Published private(set) var dockToast: String?
    @Published private(set) var lockedShakeAt: Date?

    let world: MoodWorld
    let stage: SoftStage
    let sparkles: SparkleScene
    private let sensor = PressSensor()
    private let haptics = Haptics()
    private let audio = AudioDirector.shared

    private(set) var language: Language = .zh
    private var hasBase = true
    private var mood: MoodKind?
    private var squeezes = 0
    private(set) var totalSqueezes = 0
    let visitStart = Date()
    private var acceptingSqueezes = false
    private var hasTaught = false
    private var lastEncourage = Date.distantPast
    private var lastNudge = Date.distantPast
    private var pending: [DispatchWorkItem] = []
    private var voiceTimer: Timer?
    private var idleTimer: Timer?
    private var tickTimer: Timer?
    private var touchStart: Date?
    private var holdTimer: Timer?
    private var running = false
    private var introStarted = false
    private var popped = false
    private var readyToastShown = false

    // Scoring
    private var params = SqueezeParameters()
    private var rhythm: RhythmScorer?
    private var breath: BreathScorer?
    private var sessionStart = CACurrentMediaTime()
    private var modeStart = CACurrentMediaTime()
    private var holdStart: Double?
    private var lastRhythmStart: Double?
    private var units: Double = 0   // energy out of 100

    init(world: MoodWorld) {
        self.world = world
        stage = SoftStage(world: world)
        sparkles = SparkleScene(world: world)
        haptics.sensor = sensor

        stage.onEdgeHit = { [weak self] point, strength in
            guard let self else { return }
            self.sparkles.edgeSplash(at: self.sparkles.toScene(point), strength: strength)
            self.haptics.edge(strength)
            self.audio.sfx("sfx_bounce", volume: Float(0.12 + 0.3 * strength))
        }
        stage.onReady = { [weak self] in
            guard let self, self.running, !self.introStarted else { return }
            self.runIntro()
        }
        stage.onPop = { [weak self] in self?.meshPop() }
        sensor.onPulse = { [weak self] pulse in self?.pulse(intensity: pulse.intensity, side: pulse.side) }
        sensor.onHold = { [weak self] down in self?.baseHold(down) }
        sensor.onMotion = { [weak self] gravity, _ in self?.applyMotion(gravity) }
        sensor.onShake = { [weak self] in
            self?.stage.scatter()
            self?.sparkles.scatter()
        }
    }

    // MARK: - Settings

    func configure(language: Language, hasBase: Bool, sensitivity: Sensitivity, mood: MoodKind?) {
        let firstTime = self.mood == nil && !running
        self.language = language
        self.hasBase = hasBase
        sensor.sensitivity = sensitivity
        sensorMissing = hasBase && !sensor.isAvailable
        touchMode = !hasBase || sensorMissing
        sensor.pulsesEnabled = !touchMode
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
        after(0.6) { [weak self] in guard let self, self.stage.modelsReady, !self.introStarted else { return }; self.runIntro() }
    }

    func stop() {
        running = false
        cancelPending()
        idleTimer?.invalidate()
        voiceTimer?.invalidate()
        holdTimer?.invalidate()
        tickTimer?.invalidate()
        sensor.stop()
        stage.stopShower()
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

    /// The pillow's screen rect changed (layout or rotation).
    func layoutChanged() {
        if let rect = stage.jellyScreenRect() { sparkles.setJellyRect(rect) }
        sparkles.spriteMoodi = !stage.usesMeshMoodi
        sparkles.setMouthPoint(stage.mouthScreenPoint())
    }

    var metrics: MoodVisitMetrics {
        MoodVisitMetrics(world: world, seconds: Date().timeIntervalSince(visitStart), squeezes: totalSqueezes, mode: mode)
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
        after(1.75) { [weak self] in self?.say("K1", clarity: 1) }
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

    /// Seconds the base (or screen) has been held, for the breath tide.
    func heldSeconds(_ now: Double = CACurrentMediaTime()) -> Double { holdStart.map { now - $0 } ?? 0 }

    // MARK: - Input

    /// Sensor pulse: one squeeze of the base.
    private func pulse(intensity: Double, side: Double) {
        switch mode {
        case .free: squeeze(intensity: intensity, side: side)
        case .rhythm: rhythmHit(intensity: intensity, side: side)
        case .breath:
            // the hold detector drives breathing; a quick tap still nudges the pillow
            if holdStart == nil { stage.kick(intensity * 0.5, side: side) }
        }
    }

    /// Sensor hold: the base is down / let go.
    private func baseHold(_ down: Bool) {
        guard mode == .breath else { return }
        if down { holdBegan(side: 0) } else { holdEnded(interrupted: false) }
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
        let earned = rhythm.started(now: now, beatTime: beatTime(now), strong: intensity >= 0.6)
        combo = rhythm.combo
        rhythmAdaptive = rhythm.adaptive
        lastHit = (Date(), rhythm.lastAccuracy)
        squeezeEffects(intensity: max(intensity, 0.4 + 0.6 * rhythm.lastAccuracy), side: side)
        if rhythm.lastAccuracy > 0 {
            audio.sfx("sfx_rhythm_hit", volume: Float(0.18 + 0.2 * rhythm.lastAccuracy))
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
        guide = q > 0 ? text("release") : text("longer")
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
        if held >= params.qOkLo, guide != text("letGo") { guide = text("letGo") }
    }

    /// The visual / haptic / sound side of one squeeze.
    private func squeezeEffects(intensity: Double, side: Double) {
        if phase == .intro { phase = .playing }
        squeezes += 1; totalSqueezes += 1
        lastSqueeze = Date()
        stage.kick(intensity, side: side)
        stage.burst(intensity, side: side)
        sparkles.burst(intensity: intensity, side: side)
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
        } else if effects, squeezes > 4, Date().timeIntervalSince(lastEncourage) > 10, !audio.isSpeaking, Double.random(in: 0...1) < 0.3 {
            lastEncourage = Date()
            say(["K8a", "K8b", "K8c"].randomElement()!)
        }
    }

    #if MOODIUM_AUTOPILOT
    func autopilotHold(_ down: Bool) { if down { holdBegan(side: 0) } else { holdEnded(interrupted: false) } }
    func autopilotBeatDelay() -> Double { let u = rhythmPhase(); return (1 - u) * rhythmPeriod }
    #endif

    // MARK: - Gifts

    private func growGift(_ i: Int) {
        guard stage.garden.grow(i) else { return }
        giftsGrown = stage.garden.grown.count
        audio.sfx(world == .candy ? "grow_candy" : "grow_nature", volume: 0.55)
        if let p = stage.screenPoint(stage.garden.center(i)) { sparkles.giftBurst(at: p) }
        let name = stage.garden.gifts[i].name(language)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { giftToast = (i, name) }
        after(2.8) { [weak self] in
            guard let self, self.giftToast?.index == i else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.giftToast = nil }
        }
    }

    // MARK: - Completion

    private func complete() {
        phase = .complete
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
        after(0.55) { [weak self] in self?.say("K10", clarity: 1) }
        after(3.05) { [weak self] in withAnimation { self?.showCard = true } }
    }

    /// Close the "Moodi is free" card and stay to play (the dock then nudges the shower).
    func dismissCard() {
        withAnimation(.easeOut(duration: 0.25)) { showCard = false }
        after(0.4) { [weak self] in self?.showReadyToast() }
    }

    func replay() {
        withAnimation(.easeOut(duration: 0.25)) { showCard = false }
        cancelPending()
        audio.stopVoice()
        stopShower()
        energy = 0; units = 0
        squeezes = 0
        readyToastShown = false
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

    // MARK: - Dock (shower + exit)

    var showerUnlocked: Bool { energy >= 1 }

    func showerPressed() {
        guard showerUnlocked else {
            // locked: wiggle and remind
            withAnimation(.default) { lockedShakeAt = Date() }
            haptics.edge(0.6)
            flashDockToast(language == .zh ? "继续捏一捏，集满能量就能用" : "Keep squeezing — fill the energy to use it")
            return
        }
        if showering { stopShower(); return }
        showering = true
        withAnimation(.easeOut(duration: 0.3)) { showCard = false }
        audio.sfx("sfx_chime", volume: 0.5)
        haptics.squeeze(0.5)
        stage.startShower { [weak self] in Task { @MainActor in self?.showering = false } }
    }

    func stopShower() {
        stage.stopShower()
        showering = false
    }

    private func showReadyToast() {
        guard !readyToastShown else { return }
        readyToastShown = true
        flashDockToast(world == .candy ? (language == .zh ? "能量满啦，下一场糖果雨吧" : "Energy full — make it rain candy!")
                                       : (language == .zh ? "能量满啦，下一场花草雨吧" : "Energy full — let the meadow shower fall!"))
    }

    private func flashDockToast(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dockToast = text }
        after(2.6) { [weak self] in
            guard let self, self.dockToast == text else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.dockToast = nil }
        }
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
        guard phase == .playing, energy > 0, energy < 1, holdStart == nil else { return }
        let now = Date()
        if now.timeIntervalSince(lastSqueeze) > 12, now.timeIntervalSince(lastNudge) > 30, !audio.isSpeaking {
            lastNudge = now
            say("K9")
        }
    }

    // MARK: - Touch mode (no base, or no motion sensor)

    func touchBegan() {
        guard touchStart == nil, acceptingSqueezes else { return }
        touchStart = Date()
        switch mode {
        case .breath:
            holdBegan(side: 0)
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
        holdTimer?.invalidate()
        switch mode {
        case .breath: holdEnded(interrupted: false)
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
        let thing = touchMode ? (language == .zh ? "屏幕" : "the screen") : (language == .zh ? "底座" : "the base")
        switch key {
        case "ready": return language == .zh ? "准备好了，就按住\(thing)" : "Press and hold \(thing) when you're ready"
        case "hold": return language == .zh ? "按住\(thing)，慢慢吸气" : "Hold \(thing), breathe in slowly"
        case "letGo": return language == .zh ? "可以松开了，慢慢呼气" : "You can let go now"
        case "longer": return language == .zh ? "可以按久一点，跟着光慢慢吸气" : "Hold a little longer, follow the light"
        case "release": return language == .zh ? "松开\(thing)，慢慢呼气" : "Let go, breathe out slowly"
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
            case .inhale: guide = text("hold")
            case .exhale: guide = text("release")
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

    private func say(_ id: String, muffled: Bool = false, clarity: Double? = nil, completion: (() -> Void)? = nil) {
        let lang = language.rawValue
        let file = muffled ? "moodi_vo_\(id)_\(lang)_muffled" : "moodi_vo_\(id)_\(lang)"
        let c = clarity ?? (muffled ? 1 : 0.15 + 0.85 * energy)
        let duration = audio.voice(file, clarity: c, completion: completion)
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
