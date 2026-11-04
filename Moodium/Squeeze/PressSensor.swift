import CoreMotion
import UIKit
import simd

/// Reads the phone's motion while it sits on the sensory bag and turns its small rocks into
/// squeeze pulses, whichever way the phone was laid on the bag (the counting itself is in `RockDetector`). Also reports gravity for
/// the props, hard jolts (picked up or shaken), and in breath mode when the bag is held down.
final class PressSensor {
    struct Pulse {
        let intensity: Double
        let side: Double
    }

    var onPulse: ((Pulse) -> Void)?
    /// Gravity in screen coordinates (x right, y up, in g) and the rock rate (rad/s, + toward screen-right).
    var onMotion: ((SIMD2<Double>, Double) -> Void)?
    var onShake: (() -> Void)?
    /// Live, about 60 times a second: energy units earned by the motion since the last call, and
    /// -1…1 how far the phone is tipped from where it rests (+ = screen-right side down).
    var onLive: ((Double, Double) -> Void)?
    /// The base is being held down (the phone stays tipped) / let go. Used by breath mode.
    var onHold: ((Bool) -> Void)?
    var isHeld: Bool { detector.isHeld }

    var sensitivity: Sensitivity = .normal { didSet { detector.scale = sensitivity.thresholdScale } }
    var pulsesEnabled = true
    /// Breath mode: holds matter and the resting tilt stays put while the bag is held.
    var holdMode = false {
        didSet {
            guard holdMode != oldValue else { return }
            let wasHeld = detector.isHeld
            detector.holdMode = holdMode
            if wasHeld, !holdMode { onHold?(false) }
        }
    }

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    private let manager = CMMotionManager()
    private var detector = RockDetector()
    private var orientation: UIInterfaceOrientation = .landscapeRight
    private var lastOrientationCheck: TimeInterval = 0
    private var suppressUntil: TimeInterval = 0
    private var lastShake: TimeInterval = 0
    private var lastMotionSend: TimeInterval = 0
    private var lastSample: TimeInterval?
    private var pendingFlow = 0.0
    private var lastLiveSend: TimeInterval = 0

    // Which way the phone actually rocks on the bag. It depends on how the phone was laid down,
    // so we learn it from the gyro: the main axis of recent rotation, in the device's x/y plane.
    private var rateSpread = simd_double2x2(0)   // decaying covariance of rotation rate (rad/s)²
    private var rockAxis = SIMD2<Double>(1, 0)   // unit rotation axis, device x/y
    private var axisAtRebase = SIMD2<Double>(1, 0)

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        refreshOrientation()
        resetAxis()
        detector.rebase()
        manager.deviceMotionUpdateInterval = 1.0 / 100
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.process(motion)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        if detector.isHeld, holdMode { onHold?(false) }
        detector.rebase()
    }

    /// Ignore motion briefly, e.g. while our own haptics shake the phone.
    func suppress(for seconds: TimeInterval) {
        suppressUntil = max(suppressUntil, CACurrentMediaTime() + seconds)
    }

    // MARK: - Processing

    /// Start by assuming the rock is about screen-up (the long sides of the bag left and right of the screen).
    private func resetAxis() {
        let up = screenAxes.up
        rockAxis = simd_normalize(SIMD2(up.x, up.y))
        axisAtRebase = rockAxis
        let prior = rockAxis * (0.5 * .pi / 180)        // weak: the first real presses take over
        rateSpread = simd_double2x2(columns: (prior * prior.x, prior * prior.y))
    }

    /// Follow the main rotation axis, only from samples that are clearly moving.
    private func learnAxis(_ w: SIMD2<Double>, dt: Double) {
        guard simd_length(w) > 0.6 * .pi / 180 else { return }
        let k = min(1, dt / 1.5)
        rateSpread = rateSpread * (1 - k) + simd_double2x2(columns: (w * w.x, w * w.y)) * k
        let a = rateSpread[0][0], b = rateSpread[0][1], c = rateSpread[1][1]
        let angle = 0.5 * atan2(2 * b, a - c)
        var axis = SIMD2(cos(angle), sin(angle))
        if simd_dot(axis, rockAxis) < 0 { axis = -axis }   // keep the sign steady
        rockAxis = axis
        // Turned a lot since we last took the rest: the tilt we follow changed meaning, start over.
        if simd_dot(rockAxis, axisAtRebase) < cos(20 * .pi / 180) {
            axisAtRebase = rockAxis
            if detector.isHeld, holdMode { onHold?(false) }
            detector.rebase()
        }
    }

    private func refreshOrientation() {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        if let o = scene?.effectiveGeometry.interfaceOrientation, o != .unknown { orientation = o }
    }

    /// Screen-right and screen-up expressed in device axes for the current interface orientation.
    private var screenAxes: (right: SIMD3<Double>, up: SIMD3<Double>) {
        switch orientation {
        case .landscapeRight: return (SIMD3(0, -1, 0), SIMD3(1, 0, 0))
        case .landscapeLeft: return (SIMD3(0, 1, 0), SIMD3(-1, 0, 0))
        case .portraitUpsideDown: return (SIMD3(-1, 0, 0), SIMD3(0, -1, 0))
        default: return (SIMD3(1, 0, 0), SIMD3(0, 1, 0))
        }
    }

    private func process(_ motion: CMDeviceMotion) {
        let now = CACurrentMediaTime()
        if now - lastOrientationCheck > 0.5 { lastOrientationCheck = now; refreshOrientation() }
        let dt = min(0.05, max(0, now - (lastSample ?? now)))
        lastSample = now

        let axes = screenAxes
        let g = SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z)
        let r = SIMD3(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z)
        let a = SIMD3(motion.userAcceleration.x, motion.userAcceleration.y, motion.userAcceleration.z)

        let screenGravity = SIMD2(simd_dot(g, axes.right), simd_dot(g, axes.up))

        // A hard jolt means the phone was picked up or shaken, not pressed on the bag.
        if simd_length(a) > 1.1 {
            if now - lastShake > 0.6 { lastShake = now; onShake?() }
            suppress(for: 0.5)
            if detector.isHeld, holdMode { onHold?(false) }
            detector.rebase()
            onMotion?(screenGravity, 0)
            return
        }

        // The rock: rotation about the learned axis, and the tilt it causes (gravity moving along
        // the direction across that axis). Both share a sign, so the rate is the tilt's speed.
        let w = SIMD2(r.x, r.y)
        learnAxis(w, dt: dt)
        let across = SIMD2(rockAxis.y, -rockAxis.x)
        let length = max(1e-6, simd_length(g))
        let tilt = asin(max(-1, min(1, simd_dot(SIMD2(g.x, g.y), across) / length))) * 180 / .pi
        let rate = simd_dot(w, rockAxis)
        // Which screen side goes down when the tilt grows, for the left/right effects.
        let toRight = simd_dot(across, SIMD2(axes.right.x, axes.right.y))
        let side: Double = abs(toRight) > 0.3 ? (toRight > 0 ? 1 : -1) : 1

        if now - lastMotionSend > 1.0 / 60 {
            lastMotionSend = now
            onMotion?(screenGravity, rate * side)
        }

        let result = detector.feed(tilt: tilt, rate: rate * 180 / .pi, now: now,
                                   muted: !pulsesEnabled || now < suppressUntil)
        pendingFlow += result.flow
        if now - lastLiveSend > 1.0 / 60 {
            lastLiveSend = now
            onLive?(pendingFlow, result.depth * side)
            pendingFlow = 0
        }
        if let pulse = result.pulse { onPulse?(Pulse(intensity: pulse.intensity, side: pulse.side * side)) }
        if let hold = result.hold { onHold?(hold == .began) }
    }
}

/// Haptics, rate-limited, that also tell the sensor to ignore the buzz they cause.
final class Haptics {
    weak var sensor: PressSensor?

    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notify = UINotificationFeedbackGenerator()
    private var lastEdge: TimeInterval = 0

    func prepare() { soft.prepare(); light.prepare() }

    func squeeze(_ intensity: Double) {
        soft.impactOccurred(intensity: CGFloat(0.45 + 0.55 * intensity))
        sensor?.suppress(for: 0.12)
    }

    func edge(_ strength: Double) {
        let now = CACurrentMediaTime()
        // a prop hitting the edge is a light tick, not a rattle: only firm hits, a few per second
        guard strength > 0.35, now - lastEdge > 0.22 else { return }
        lastEdge = now
        light.impactOccurred(intensity: CGFloat(0.25 + 0.5 * min(1, strength)))
        sensor?.suppress(for: 0.06)
    }

    func gift() {
        rigid.impactOccurred(intensity: 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.rigid.impactOccurred(intensity: 0.6) }
        sensor?.suppress(for: 0.3)
    }

    func success() {
        notify.notificationOccurred(.success)
        sensor?.suppress(for: 0.4)
    }
}
