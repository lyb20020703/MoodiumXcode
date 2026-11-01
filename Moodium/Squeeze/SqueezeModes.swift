import Foundation

/// The three ways to squeeze from the visionOS app (SqueezeModeController):
/// free (every squeeze counts), rhythm (squeeze on the beat, combos pay more) and
/// breath (hold to breathe in about four seconds, let go to breathe out).
enum SqueezeMode: String, CaseIterable, Identifiable {
    case free, rhythm, breath
    var id: String { rawValue }

    func name(_ l: Language) -> String {
        switch self {
        case .free: return l == .zh ? "自由" : "Free"
        case .rhythm: return l == .zh ? "节奏" : "Rhythm"
        case .breath: return l == .zh ? "呼吸" : "Breath"
        }
    }

    func toast(_ l: Language) -> String {
        switch self {
        case .free: return l == .zh ? "自由模式" : "Free mode"
        case .rhythm: return l == .zh ? "节奏模式" : "Rhythm mode"
        case .breath: return l == .zh ? "呼吸模式" : "Breath mode"
        }
    }

    var icon: String { "mode_icon_\(rawValue)" }
}

/// SqueezeParameters (energy is out of 100, as in CandyEnergyController).
struct SqueezeParameters {
    var bpm = 89.0, beatsPerSqueeze = 2.0, inputLatency = 0.05
    var window = 0.22, assistWindow = 0.34, base = 0.6, rhythm = 1.25, strength = 0.3
    var comboStep = 0.06, rushBonus = 2.0, spamHard = 0.55, spamHardMult = 0.25, spamSoft = 0.85, spamSoftMult = 0.6
    var comboCap = 8, rushEvery = 8, adaptMisses = 4
    var adaptMin = 0.9, adaptMax = 2.2, rate = 0.5, inhale = 4.0, fadeEnd = 6.0
    var breathBonus = 5.5, qLo = 1.2, qOkLo = 3.0, qOkHi = 5.5, qHi = 8.0
    var exhaleBonus = 3.5, exhaleOk = 5.0, floor = 0.8, floorMinGap = 1.2, floorSpamMult = 0.2
    var earlyComboBoost = false

    var rhythmPeriod: Double { 60 / max(1, bpm) * max(1, beatsPerSqueeze) }

    /// SqueezeTuning.ForMood: a low mood gets a wider window, a tense one a longer exhale.
    static func forMood(_ mood: MoodKind?) -> SqueezeParameters {
        var p = SqueezeParameters()
        if mood == .low { p.window = 0.28; p.earlyComboBoost = true }
        if mood == .tense { p.exhaleOk = 6 }
        return p
    }
}

/// EnergyAssist: rhythm and breath pay up to 2.5× after 75 s so nobody gets stuck.
func energyAssist(elapsed: Double, mode: SqueezeMode) -> Double {
    mode == .free ? 1 : 1 + 1.5 * max(0, min(1, (elapsed - 75) / 75))
}

/// RhythmScorer.cs
final class RhythmScorer {
    let p: SqueezeParameters
    private(set) var combo = 0
    private(set) var adaptive = false
    private(set) var lastAccuracy = 0.0
    private(set) var lastRush = false
    private(set) var adaptiveInterval: Double
    private(set) var lastStart = Double.nan
    private var misses = 0, hits = 0

    init(_ p: SqueezeParameters) { self.p = p; adaptiveInterval = p.rhythmPeriod }

    static func accuracy(_ error: Double, _ window: Double) -> Double { max(0, min(1, 1 - abs(error) / max(0.001, window))) }

    private func spam(_ gap: Double) -> Double { gap < p.spamHard ? p.spamHardMult : gap < p.spamSoft ? p.spamSoftMult : 1 }

    /// Phase 0…1 of the beat at `beatTime` (0 = on the beat).
    func phase(now: Double, beatTime: Double) -> Double {
        let t = adaptive && !lastStart.isNaN ? (now - lastStart) / adaptiveInterval : (beatTime - p.inputLatency) / p.rhythmPeriod
        return t - t.rounded(.down)
    }

    /// A squeeze started; returns the energy it earns.
    func started(now: Double, beatTime: Double, strong: Bool) -> Double {
        let gap = lastStart.isNaN ? Double.infinity : now - lastStart
        let phase = (beatTime - p.inputLatency) / p.rhythmPeriod
        let error = adaptive && !lastStart.isNaN ? abs(now - lastStart - adaptiveInterval) : abs(phase - phase.rounded()) * p.rhythmPeriod
        lastAccuracy = Self.accuracy(error, adaptive ? p.assistWindow : p.window)
        if lastAccuracy > 0 { combo += 1; misses = 0; hits += 1 } else { combo = 0; misses += 1 }
        let mult = 1 + p.comboStep * (p.earlyComboBoost && hits <= 8 ? 2 : 1) * Double(min(combo, p.comboCap))
        lastRush = combo > 0 && combo % max(1, p.rushEvery) == 0
        let energy = (p.base + p.rhythm * lastAccuracy + (strong ? p.strength : 0)) * mult * spam(gap) + (lastRush ? p.rushBonus : 0)
        if !adaptive && misses >= p.adaptMisses {
            adaptive = true
            adaptiveInterval = max(p.adaptMin, min(p.adaptMax, gap.isFinite ? gap : p.rhythmPeriod))
        } else if adaptive && gap.isFinite {
            adaptiveInterval = max(p.adaptMin, min(p.adaptMax, adaptiveInterval * 0.7 + gap * 0.3))
        }
        lastStart = now
        return max(0, energy)
    }
}

/// BreathScorer.cs
final class BreathScorer {
    let p: SqueezeParameters
    private var released = Double.nan
    private(set) var lastQuality = 0.0
    private(set) var breaths = 0

    init(_ p: SqueezeParameters) { self.p = p }

    /// 0 under 1.2 s, ramps to 1 at 3 s, 1 until 5.5 s, back to 0 at 8 s.
    func quality(_ t: Double) -> Double {
        t < p.qLo || t > p.qHi ? 0 : t < p.qOkLo ? (t - p.qLo) / (p.qOkLo - p.qLo) : t <= p.qOkHi ? 1 : (p.qHi - t) / (p.qHi - p.qOkHi)
    }

    private func holdIntegral(_ hold: Double) -> Double {
        let first = max(0, min(p.inhale, hold))
        let span = max(0.001, p.fadeEnd - p.inhale)
        let tail = max(0, min(span, hold - p.inhale))
        return p.rate * (first + tail - tail * tail / (2 * span))
    }

    func started(now: Double) -> Double {
        let gap = released.isNaN ? Double.infinity : now - released
        let exhale = released.isNaN ? 0 : max(0, min(1, (gap - 2) / max(0.001, p.exhaleOk - 2)))
        return p.exhaleBonus * exhale + p.floor * (gap >= p.floorMinGap ? 1 : p.floorSpamMult)
    }

    func held(seconds: Double, dt: Double) -> Double { holdIntegral(seconds) - holdIntegral(max(0, seconds - dt)) }

    func released(now: Double, held: Double) -> Double {
        released = now
        lastQuality = quality(held)
        if lastQuality > 0 { breaths += 1 }
        return p.breathBonus * lastQuality
    }
}
