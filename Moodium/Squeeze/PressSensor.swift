import CoreMotion
import UIKit
import simd

/// Reads the phone's motion while it sits on the sensory bag and turns its small left/right
/// rocks into squeeze pulses (the counting itself is in `RockDetector`). Also reports gravity for
/// the props, hard jolts (picked up or shaken), and in breath mode when the bag is held down.
final class PressSensor {
    struct Pulse {
        let intensity: Double
        let side: Double
    }

    var onPulse: ((Pulse) -> Void)?
    /// Gravity in screen coordinates (x right, y up, in g) and left/right rock rate (rad/s).
    var onMotion: ((SIMD2<Double>, Double) -> Void)?
    var onShake: (() -> Void)?
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

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        refreshOrientation()
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

        let axes = screenAxes
        let g = SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z)
        let r = SIMD3(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z)
        let a = SIMD3(motion.userAcceleration.x, motion.userAcceleration.y, motion.userAcceleration.z)

        let screenGravity = SIMD2(simd_dot(g, axes.right), simd_dot(g, axes.up))
        // Rotation about screen-up is the left/right rock, the only way the bag moves the phone.
        let rockLR = simd_dot(r, axes.up)

        if now - lastMotionSend > 1.0 / 60 {
            lastMotionSend = now
            onMotion?(screenGravity, rockLR)
        }

        // A hard jolt means the phone was picked up or shaken, not pressed on the bag.
        if simd_length(a) > 1.1 {
            if now - lastShake > 0.6 { lastShake = now; onShake?() }
            suppress(for: 0.5)
            if detector.isHeld, holdMode { onHold?(false) }
            detector.rebase()
            return
        }

        // Left/right tilt in degrees; + when the right edge is lower.
        let length = max(1e-6, simd_length(g))
        let tilt = asin(max(-1, min(1, simd_dot(g, axes.right) / length))) * 180 / .pi
        let result = detector.feed(tilt: tilt, rate: rockLR * 180 / .pi, now: now,
                                   muted: !pulsesEnabled || now < suppressUntil)
        if let pulse = result.pulse { onPulse?(Pulse(intensity: pulse.intensity, side: pulse.side)) }
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
        guard now - lastEdge > 0.07 else { return }
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
