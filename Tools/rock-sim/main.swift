// Simulated bag presses through RockDetector. Run from the repo root:
// swiftc -O Tools/rock-sim/main.swift Moodium/Squeeze/RockDetector.swift -o /tmp/rock-sim && /tmp/rock-sim

import Foundation

var rng = SystemRandomNumberGenerator()
func noise(_ a: Double) -> Double { Double.random(in: -a...a, using: &rng) }

/// Runs a tilt curve (degrees over time) through the detector at 100 Hz.
func run(_ name: String, seconds: Double, scale: Double = 1, holdMode: Bool = false, noiseAmp: Double = 0.01, gyroNoise: Double = 0.6,
         expect: ClosedRange<Int>, holds: Int? = nil, energy: ClosedRange<Double>? = nil, _ curve: (Double) -> Double) {
    var d = RockDetector(); d.scale = scale; d.holdMode = holdMode
    var pulses = 0, holdEvents: [String] = [], units = 0.0, deepest = 0.0
    var prev = curve(0)
    var t = 0.0
    while t < seconds {
        let clean = curve(t)
        let v = clean + noise(noiseAmp)                 // fused gravity: small angle noise
        let rate = (clean - prev) * 100 + noise(gyroNoise)    // gyro: true rate plus noise (0.6 °/s is a pessimistic default)
        prev = clean
        let r = d.feed(tilt: v, rate: rate, now: t)
        if r.pulse != nil { pulses += 1 }
        units += r.flow; deepest = max(deepest, r.depth)
        if let h = r.hold { holdEvents.append(h == .began ? "B@\(String(format: "%.1f", t))" : "E@\(String(format: "%.1f", t))") }
        t += 0.01
    }
    let okP = expect.contains(pulses)
    let okH = holds.map { $0 == holdEvents.count } ?? true
    let okE = energy.map { $0.contains(units) } ?? true
    print("\(okP && okH && okE ? "PASS" : "FAIL")  \(name): \(pulses) squeezes (want \(expect)), energy \(String(format: "%.1f", units))"
          + (energy.map { " (want \($0))" } ?? "") + ", pillow \(Int(deepest * 100))%" + (holdMode ? "  holds \(holdEvents)" : ""))
}

/// One press: dips to `depth` over `down` s, stays `hold` s, comes back over `up` s (with damped wobble).
func press(_ t: Double, at start: Double, depth: Double, down: Double = 0.12, hold: Double = 0.05, up: Double = 0.18, wobble: Double = 0) -> Double {
    let u = t - start
    if u < 0 { return 0 }
    if u < down { return depth * (1 - cos(.pi * u / down)) / 2 }
    if u < down + hold { return depth }
    if u < down + hold + up { let k = (u - down - hold) / up; return depth * (1 + cos(.pi * k)) / 2 }
    let w = u - down - hold - up
    return -depth * wobble * exp(-w * 8) * sin(w * 2 * .pi * 4)
}

// 1. alternating left/right presses, 0.6° each, 3 per second, for 5 s
run("左右交替快速按 0.25°", seconds: 5.2, expect: 14...16) { t in
    let i = Int(t / 0.333); let s = Double(i).truncatingRemainder(dividingBy: 2) == 0 ? 1.0 : -1.0
    return press(t, at: Double(i) * 0.333, depth: 0.25 * s, down: 0.12, hold: 0.04, up: 0.15)
}
// 2. pressing the same side again and again, 0.5°, every 0.4 s
run("同一侧连续按 0.2°", seconds: 4.1, expect: 11...11) { t in
    let i = Int(t / 0.4); return press(t, at: Double(i) * 0.4, depth: -0.2)
}
// 3. gentle presses 0.4° once a second
run("轻按 0.18°，每秒一次", seconds: 6, expect: 6...6) { t in
    let i = Int(t); return press(t, at: Double(i), depth: 0.18, down: 0.2, hold: 0.2, up: 0.3)
}
// 4. very light 0.3° presses: missed at 适中, counted at 灵敏
run("很轻 0.1°（适中）", seconds: 5, expect: 0...5) { t in let i = Int(t); return press(t, at: Double(i), depth: 0.1) }
run("很轻 0.1°（灵敏）", seconds: 5, scale: 0.7, expect: 5...5) { t in let i = Int(t); return press(t, at: Double(i), depth: 0.3) }
// 5. strong presses 3° with wobble on release
run("用力按 3°，松手回弹 20%", seconds: 5, expect: 5...5) { t in
    let i = Int(t); return press(t, at: Double(i), depth: 3, down: 0.1, hold: 0.1, up: 0.15, wobble: 0.2)
}
// 6. only sensor noise
run("放着不动（噪声 0.03°）", seconds: 10, noiseAmp: 0.03, expect: 0...0, energy: 0...1) { _ in 0 }
// 7. slow drift 2° over 8 s (phone settling into the bag)
run("慢慢下沉 2°/8 秒", seconds: 10, expect: 0...0, energy: 0...2) { t in min(2, t / 4) }
// 8. phone rests tilted 1.5°, then presses on both sides
run("本身斜放 1.5° 再左右按 0.25°", seconds: 6, expect: 4...4) { t in
    1.5 + (t > 2 ? press(t, at: 2.5, depth: 0.25) + press(t, at: 3.5, depth: -0.25) + press(t, at: 4.5, depth: 0.25) + press(t, at: 5.3, depth: -0.25) : 0)
}
// 5b. alternating hard left 3° and light right 0.9°
run("左重 3° 右轻 0.9° 交替", seconds: 4, expect: 8...8) { t in
    let i = Int(t / 0.5); return press(t, at: Double(i) * 0.5, depth: i % 2 == 0 ? -3 : 0.9, down: 0.12, hold: 0.05, up: 0.15)
}
// 5c. a bag that bounces a lot: 35% overshoot after 2° presses
run("回弹很大 35%（极端情况，仅参考，可能多算）", seconds: 5, expect: 5...10) { t in
    let i = Int(t); return press(t, at: Double(i), depth: 2, down: 0.1, hold: 0.1, up: 0.15, wobble: 0.35)
}
// 9. breath mode: hold 1.5° for 4 s, twice
run("呼吸模式按住 4 秒 ×2", seconds: 12, holdMode: true, expect: 2...2, holds: 4) { t in
    press(t, at: 1, depth: 1.5, down: 0.4, hold: 4, up: 0.6) + press(t, at: 7, depth: -1.5, down: 0.4, hold: 4, up: 0.6)
}

// 10. like a spirit level: tiny presses that never count as a squeeze still fill the bar
run("极轻 0.05°，每秒一次，真机级噪声（不算捏，但进度要涨）", seconds: 6, gyroNoise: 0.15, expect: 0...0, energy: 0.5...40) { t in
    let i = Int(t); return press(t, at: Double(i), depth: 0.05, down: 0.12, hold: 0.05, up: 0.18)
}
run("轻按 0.18°，真机级噪声", seconds: 6, noiseAmp: 0.005, gyroNoise: 0.15, expect: 6...6) { t in
    let i = Int(t); return press(t, at: Double(i), depth: 0.18, down: 0.2, hold: 0.2, up: 0.3)
}
run("放着不动，真机级噪声", seconds: 10, noiseAmp: 0.005, gyroNoise: 0.15, expect: 0...0, energy: 0...0.5) { _ in 0 }
