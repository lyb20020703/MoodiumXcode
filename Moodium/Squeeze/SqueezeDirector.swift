import SwiftUI
import SceneKit
import SpriteKit

/// Runs the squeeze rescue (ported from MoodiRescueDirector) on the phone:
/// Moodi falls into the pillow, asks for help with a muffled voice, each squeeze of the base
/// fills the energy ring and sprays the world's props, Moodi's voice gets clearer as energy
/// rises, and at 100 % the pillow pops and Moodi jumps out.
@MainActor
final class SqueezeDirector: ObservableObject {
    enum Phase { case intro, playing, complete }

    @Published private(set) var phase: Phase = .intro
    @Published private(set) var energy: Double = 0
    @Published private(set) var lastSqueeze = Date()
    @Published private(set) var subtitle: String?
    @Published private(set) var showHint = false
    @Published private(set) var showCard = false
    @Published private(set) var touchMode = false
    @Published private(set) var sensorMissing = false

    let world: MoodWorld
    let stage: SoftStage
    let sparkles: SparkleScene
    private let sensor = PressSensor()
    private let haptics = Haptics()
    private let audio = AudioDirector.shared

    private(set) var language: Language = .zh
    private var hasBase = true
    private var squeezes = 0
    private var acceptingSqueezes = false
    private var hasTaught = false
    private var lastEncourage = Date.distantPast
    private var lastNudge = Date.distantPast
    private var pending: [DispatchWorkItem] = []
    private var idleTimer: Timer?
    private var touchStart: Date?
    private var holdTimer: Timer?
    private var running = false

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
        sensor.onPulse = { [weak self] pulse in self?.squeeze(intensity: pulse.intensity, side: pulse.side) }
        sensor.onMotion = { [weak self] gravity, _ in self?.applyMotion(gravity) }
        sensor.onShake = { [weak self] in
            self?.stage.scatter()
            self?.sparkles.scatter()
        }
    }

    // MARK: - Settings

    func configure(language: Language, hasBase: Bool, sensitivity: Sensitivity) {
        self.language = language
        self.hasBase = hasBase
        sensor.sensitivity = sensitivity
        sensorMissing = hasBase && !sensor.isAvailable
        touchMode = !hasBase || sensorMissing
        sensor.pulsesEnabled = !touchMode
    }

    // MARK: - Life cycle

    func start() {
        guard !running else { return }
        running = true
        #if MOODIUM_AUTOPILOT
        AutopilotHooks.director = self
        #endif
        audio.playMusic(world.bgm)
        haptics.prepare()
        sensor.start()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdle() }
        }
        after(0.6) { [weak self] in self?.runIntro() }
    }

    func stop() {
        running = false
        cancelPending()
        idleTimer?.invalidate()
        holdTimer?.invalidate()
        sensor.stop()
        audio.stopVoice()
        audio.stopMusic()
    }

    func pause() {
        sensor.stop()
        audio.pauseAll()
        sparkles.isPaused = true
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
    }

    // MARK: - Story

    private func runIntro() {
        phase = .intro
        acceptingSqueezes = false
        showHint = false
        layoutChanged()
        audio.sfx("sfx_hop", volume: 0.5)
        sparkles.moodiFallIn { [weak self] in
            guard let self else { return }
            // K1 just before the splash, then the pillow swallows Moodi.
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
        after(1.75) { [weak self] in self?.say("K1", clarity: 1) }
    }

    private func beginPlay() {
        guard phase == .intro else { return }
        phase = .playing
        lastSqueeze = Date()
        withAnimation(.easeOut(duration: 0.4)) { showHint = true }
    }

    // MARK: - Squeezing

    /// One squeeze of the base (or a press-and-release in touch mode).
    func squeeze(intensity: Double, side: Double) {
        guard acceptingSqueezes, phase != .complete else { return }
        if phase == .intro { phase = .playing }
        squeezes += 1
        lastSqueeze = Date()

        stage.kick(intensity, side: side)
        stage.burst(intensity, side: side)
        sparkles.burst(intensity: intensity, side: side)
        haptics.squeeze(intensity)
        audio.sfx("sfx_squish", volume: Float(0.25 + 0.35 * intensity))

        let before = energy
        energy = min(1, energy + 0.024 + 0.03 * intensity)
        sparkles.setEnergy(energy)
        sparkles.moodiReact(energy: energy, intensity: intensity)

        if squeezes >= 3, showHint { withAnimation(.easeOut(duration: 0.5)) { showHint = false } }

        let gifts: [(Double, String)] = [(0.2, "K5"), (0.5, "K6"), (0.8, "K7")]
        if energy >= 1 {
            complete()
        } else if let gift = gifts.first(where: { before < $0.0 && energy >= $0.0 }) {
            haptics.gift()
            audio.sfx("sfx_chime", volume: 0.55)
            sparkles.giftBurst()
            say(gift.1)
        } else if squeezes == 1 {
            say("K4")
        } else if squeezes > 4, Date().timeIntervalSince(lastEncourage) > 10, !audio.isSpeaking, Double.random(in: 0...1) < 0.3 {
            lastEncourage = Date()
            say(["K8a", "K8b", "K8c"].randomElement()!)
        }
    }

    private func complete() {
        phase = .complete
        acceptingSqueezes = false
        withAnimation { showHint = false }
        haptics.success()
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

    func replay() {
        withAnimation(.easeOut(duration: 0.25)) { showCard = false }
        cancelPending()
        audio.stopVoice()
        energy = 0
        squeezes = 0
        sparkles.setEnergy(0)
        sparkles.moodiLeave()
        stage.clearProps()
        stage.regrowJelly()
        after(0.7) { [weak self] in self?.runIntro() }
    }

    private func checkIdle() {
        guard phase == .playing, energy > 0, energy < 1 else { return }
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
        holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let start = self.touchStart else { return }
                self.stage.setHold(min(1, Date().timeIntervalSince(start) / 0.6))
            }
        }
    }

    func touchEnded(atX x: CGFloat, width: CGFloat) {
        guard let start = touchStart else { return }
        touchStart = nil
        holdTimer?.invalidate()
        stage.setHold(0)
        let held = min(1, Date().timeIntervalSince(start) / 0.6)
        let side = width > 0 ? Double((x / width - 0.5) * 2) : 0
        squeeze(intensity: 0.35 + 0.65 * held, side: max(-1, min(1, side)))
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

/// Moodi's lines from moodi_rescue_voice_lines.csv.
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
    ]

    static func text(_ id: String, _ language: Language) -> String {
        guard let pair = lines[id] else { return "" }
        return language == .zh ? pair.0 : pair.1
    }
}
