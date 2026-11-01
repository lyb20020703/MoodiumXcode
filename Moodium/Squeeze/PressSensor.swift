import CoreMotion
import UIKit
import simd

/// Turns the phone's rocking on the sensory base into squeeze pulses.
///
/// The phone sits in the middle of the pillow-shaped base. Pressing one side tips the phone,
/// which the gyroscope sees as a short burst of rotation. We watch the rotation rate in the
/// screen plane, keep an adaptive noise floor, and emit one pulse per burst with an intensity
/// from its peak and a side (-1 left, +1 right, 0 middle) from which edge dipped first.
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
    private(set) var isHeld = false

    var sensitivity: Sensitivity = .normal
    var pulsesEnabled = true

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    private let manager = CMMotionManager()
    private var orientation: UIInterfaceOrientation = .landscapeRight
    private var lastOrientationCheck: TimeInterval = 0

    private enum State { case idle, rising, cooldown }
    private var state = State.idle
    private var noiseFloor = 0.06
    private var peak = 0.0
    private var peakSide = 0.0
    private var riseStart: TimeInterval = 0
    private var lastPulse: TimeInterval = 0
    private var suppressUntil: TimeInterval = 0
    private var lastShake: TimeInterval = 0
    private var lastMotionSend: TimeInterval = 0

    // Hold detection: how far gravity has tipped away from where the phone rests.
    private var restGravity: SIMD3<Double>?
    private var tipSince: TimeInterval?
    private var settleSince: TimeInterval?
    private var heldSince: TimeInterval = 0
    private var releasedAt: TimeInterval = 0

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        refreshOrientation()
        manager.deviceMotionUpdateInterval = 1.0 / 100
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.process(motion)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        state = .idle
        if isHeld { isHeld = false; onHold?(false) }
        restGravity = nil
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
        // Rotation about screen-up tips the left/right edges; about screen-right tips top/bottom.
        let rockLR = simd_dot(r, axes.up)
        let rockFB = simd_dot(r, axes.right)
        let magnitude = (rockLR * rockLR + rockFB * rockFB).squareRoot()

        if now - lastMotionSend > 1.0 / 60 {
            lastMotionSend = now
            onMotion?(screenGravity, rockLR)
        }

        // A hard jolt means the phone was picked up or shaken, not pressed on the base.
        if simd_length(a) > 1.1 {
            if now - lastShake > 0.6 { lastShake = now; onShake?() }
            suppress(for: 0.5)
            state = .idle
            restGravity = nil
            if isHeld { isHeld = false; releasedAt = now; onHold?(false) }
            return
        }

        let k = sensitivity.thresholdScale
        trackHold(simd_normalize(g), now: now, k: k)
        let threshold = max(0.32 * k, noiseFloor * 4.5 * k)

        switch state {
        case .idle:
            guard pulsesEnabled, now >= suppressUntil, now - lastPulse > 0.25 else {
                if magnitude < threshold { trackNoise(magnitude) }
                return
            }
            if magnitude > threshold {
                state = .rising
                peak = magnitude
                riseStart = now
                // Positive rate about screen-up dips the right edge: the right side was pressed.
                peakSide = abs(rockLR) > abs(rockFB) * 0.6 ? (rockLR > 0 ? 1 : -1) : 0
            } else {
                trackNoise(magnitude)
            }
        case .rising:
            if magnitude > peak { peak = magnitude }
            if magnitude < peak * 0.55 || now - riseStart > 0.12 {
                let intensity = min(1, max(0.2, (peak - threshold) / (2.2 * k) + 0.2))
                lastPulse = now
                state = .cooldown
                // The pillow springing back after a long hold is a release, not a new squeeze.
                let isRelease = (isHeld && now - heldSince > 0.35) || now - releasedAt < 0.3
                if !isRelease { onPulse?(Pulse(intensity: intensity, side: peakSide)) }
            }
        case .cooldown:
            // Let the rebound of the pillow settle before listening again.
            if magnitude < threshold * 0.7 && now - lastPulse > 0.22 { state = .idle }
        }
    }

    /// Pressing the base tips the phone and keeps it tipped while the hand stays down.
    /// Gravity drifting more than ~1.8° from the resting direction for 0.1 s is a hold; back
    /// within ~0.9° for 0.12 s is a release. The resting direction follows slowly while idle.
    private func trackHold(_ g: SIMD3<Double>, now: TimeInterval, k: Double) {
        guard pulsesEnabled else { return }
        guard let rest = restGravity else { restGravity = g; return }
        let angle = acos(max(-1, min(1, simd_dot(g, rest)))) * 180 / .pi
        let on = 1.8 * k, off = 0.9 * k
        if !isHeld {
            if angle > on, now >= suppressUntil {
                if tipSince == nil { tipSince = now }
                if now - tipSince! >= 0.1 {
                    isHeld = true; heldSince = now; settleSince = nil
                    onHold?(true)
                }
            } else {
                tipSince = nil
                // follow slow drift (≈2.5 s) only while resting
                restGravity = simd_normalize(rest + (g - rest) * 0.004)
            }
        } else {
            if angle < off {
                if settleSince == nil { settleSince = now }
                if now - settleSince! >= 0.12 { release(now) }
            } else {
                settleSince = nil
            }
            // Someone moved the phone or leaned on it for ages: take this as the new rest.
            if now - heldSince > 15 { restGravity = g; release(now) }
        }
    }

    private func release(_ now: TimeInterval) {
        isHeld = false; tipSince = nil; settleSince = nil; releasedAt = now
        onHold?(false)
    }

    private func trackNoise(_ magnitude: Double) {
        noiseFloor = min(0.4, max(0.02, noiseFloor * 0.985 + magnitude * 0.015))
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
