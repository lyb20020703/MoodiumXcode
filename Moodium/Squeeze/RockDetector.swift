import Foundation

/// Turns the phone's left/right tilt on the sensory bag into squeezes.
///
/// The bag only takes presses on its left and right sides, so the phone just rocks a little
/// sideways (often a tenth of a degree or two). We follow that one tilt angle and count a squeeze each
/// time the phone dips away from where it rests by a small swing. Coming back (letting go) never
/// counts, but pressing again, or pressing the other side, always does, however fast.
///
/// Plain Swift with no CoreMotion, so it can be tested on a Mac with recorded or made-up tilts.
struct RockDetector {
    struct Pulse: Equatable {
        /// 0.2…1, from how fast the phone dipped.
        var intensity: Double
        /// -1 the left side went down, +1 the right side.
        var side: Double
    }

    enum Hold { case began, ended }

    // Tuning, in degrees and seconds, at the "适中" sensitivity (multiplied by `scale`).
    /// Tilt change since the last turn that counts as one squeeze.
    static let swing = 0.15
    /// The dip must move at least this fast (°/s), so slow settling never counts.
    static let minRate = 0.8
    /// Rate (°/s) that gives full intensity.
    static let fullRate = 18.0
    /// Breath mode: tipped this far from rest for 0.1 s is a hold, back within `holdOff` for 0.12 s lets go.
    static let holdOn = 0.5
    static let holdOff = 0.25
    /// Shortest time between two squeezes.
    static let gap = 0.12
    /// Continuous energy, like the Level in Apple's Measure app: no threshold to reach, any
    /// back-and-forth rocking above this phone's own sensor noise fills the bar, faster rocking
    /// fills it faster, up to `flowMax` units/s (energy is out of 100); `flowSoft` °/s above the
    /// noise gets ~63 % of the max. The noise floor is measured live, within `flowFloor`.
    static let flowFloor = 0.12...0.6
    static let flowSoft = 0.8
    static let flowMax = 12.0
    /// Tilt (°) that shows the pillow fully pressed.
    static let fullDepth = 0.6

    /// Sensitivity: below 1 is more sensitive.
    var scale = 1.0
    /// Breath mode: the base is held for seconds at a time, so keep the resting tilt steady.
    var holdMode = false

    private(set) var rest: Double?
    private(set) var isHeld = false

    private var anchor = 0.0        // tilt at the last turn
    private var extreme = 0.0       // furthest tilt in the current direction
    private var direction = 0.0     // +1 tilting right, -1 left, 0 not moving yet
    private var armed = true        // this swing has not counted yet
    private var swingRate = 0.0     // fastest °/s since the last turn
    private var smoothRate = 0.0    // |rate| lightly smoothed, so one noisy sample can't pass `minRate`
    private var peak = 0.0          // deepest recent tilt from rest (signed), to tell bounces from presses
    private var peakTime = -Double.infinity
    private var lastPulse = -Double.infinity
    private var lastTime: Double?
    private var drift = 0.0         // rate (°/s) slowly averaged: steady settling, not rocking
    private var wobble = 0.0        // |rate − drift| smoothed: how much the phone rocks right now
    private var noise = 0.15        // quietest recent `wobble`: this phone's sensor noise
    private var quietFor = 0.0
    private var tipSince: Double?
    private var settleSince: Double?
    private var heldSince = 0.0

    /// Forget where the phone rests (it was picked up or moved); the next sample becomes rest.
    mutating func rebase() {
        rest = nil
        peak = 0
        direction = 0
        armed = true
        tipSince = nil
        settleSince = nil
    }

    /// One sample. `tilt` in degrees (+ = right edge lower), `rate` its speed in °/s,
    /// `muted` while our own haptics shake the phone or squeezes are off.
    /// Returns a squeeze and/or a hold change (`hold` only fires in hold mode), `flow`: energy units
    /// earned by this sample's motion, and `depth`: -1…1 how far the phone is tipped from rest (signed like `tilt`).
    mutating func feed(tilt: Double, rate: Double, now: Double, muted: Bool = false)
        -> (pulse: Pulse?, hold: Hold?, flow: Double, depth: Double) {
        let dt = min(0.05, max(0, now - (lastTime ?? now)))
        lastTime = now
        guard let r = rest else {
            rest = tilt; anchor = tilt; extreme = tilt; direction = 0; armed = true; swingRate = 0
            if isHeld { isHeld = false; return (nil, holdMode ? .ended : nil, 0, 0) }
            return (nil, nil, 0, 0)
        }
        let off = tilt - r
        smoothRate += (abs(rate) - smoothRate) * 0.35
        let speed = smoothRate
        let swing = Self.swing * scale
        let turn = swing * 0.5

        // Still for a moment: start fresh from here, so the next press always counts.
        quietFor = speed < Self.minRate * scale * 0.7 ? quietFor + dt : 0
        if quietFor > 0.3, direction != 0, abs(tilt - extreme) < turn {
            anchor = tilt; extreme = tilt; direction = 0; armed = true; swingRate = 0
        }

        // Follow the swing and notice when it turns around.
        if direction == 0 {
            if abs(tilt - anchor) >= turn {
                direction = tilt > anchor ? 1 : -1
                extreme = tilt
            }
        } else if (tilt - extreme) * direction > 0 {
            extreme = tilt
        } else if (extreme - tilt) * direction >= turn {
            anchor = extreme; extreme = tilt; direction = -direction; armed = true; swingRate = 0
            if abs(anchor - r) >= abs(recentPeak(now)) { peak = anchor - r; peakTime = now }
        }
        swingRate = max(swingRate, speed)

        // A squeeze: moved a full swing since the last turn, away from rest (not on the way back).
        // Right after a deep press, the next one must go at least a quarter as deep, so the bag
        // wobbling after a hard press isn't counted again.
        let crossing = abs(recentPeak(now)) * 0.25
        var pulse: Pulse?
        if armed, direction != 0, !muted, now - lastPulse >= Self.gap,
           (tilt - anchor) * direction >= swing,
           off * direction >= max(turn, crossing),
           swingRate >= Self.minRate * scale {
            armed = false
            lastPulse = now
            let intensity = 0.2 + 0.8 * (swingRate - Self.minRate * scale) / (Self.fullRate * scale)
            pulse = Pulse(intensity: min(1, max(0.2, intensity)), side: direction)
        }

        // Continuous energy: only the back-and-forth part of the motion, above the sensor noise.
        drift += (rate - drift) * min(1, dt / 0.6)
        wobble += (abs(rate - drift) - wobble) * 0.35
        noise += (wobble - noise) * min(1, dt / (wobble < noise ? 1 : 20))
        let floor = min(Self.flowFloor.upperBound, max(Self.flowFloor.lowerBound, noise * 3.5)) * scale
        let moving = max(0, wobble - floor)
        let flow = muted ? 0 : Self.flowMax * (1 - exp(-moving / (Self.flowSoft * scale))) * dt
        let depth = max(-1, min(1, off / (Self.fullDepth * scale)))

        let hold = holdMode ? trackHold(off, tilt: tilt, now: now, muted: muted) : nil
        if !holdMode, isHeld { isHeld = false; tipSince = nil }

        // Slowly follow where the phone rests (it settles into the bag, or the bag sags).
        if holdMode {
            if !isHeld, tipSince == nil { rest = r + off * min(1, dt / 2.5) }
        } else if quietFor > 0.6 {
            rest = r + off * min(1, dt / 1.0)
        }
        return (pulse, hold, flow, depth)
    }

    /// The deepest press of the last moment: kept for 0.4 s, then fading.
    private func recentPeak(_ now: Double) -> Double {
        let age = now - peakTime
        return age < 0.4 ? peak : peak * exp(-(age - 0.4) / 0.3)
    }

    private mutating func trackHold(_ off: Double, tilt: Double, now: Double, muted: Bool) -> Hold? {
        let on = Self.holdOn * scale, release = Self.holdOff * scale
        if !isHeld {
            guard abs(off) > on, !muted else { tipSince = nil; return nil }
            if tipSince == nil { tipSince = now }
            guard now - tipSince! >= 0.1 else { return nil }
            isHeld = true; heldSince = now; settleSince = nil
            return .began
        }
        // Someone moved the phone or leaned on it for ages: take this as the new rest.
        if now - heldSince > 15 {
            rest = tilt; isHeld = false; tipSince = nil; settleSince = nil
            return .ended
        }
        guard abs(off) < release else { settleSince = nil; return nil }
        if settleSince == nil { settleSince = now }
        guard now - settleSince! >= 0.12 else { return nil }
        isHeld = false; tipSince = nil; settleSince = nil
        return .ended
    }
}
