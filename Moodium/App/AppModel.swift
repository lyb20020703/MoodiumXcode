import SwiftUI

enum Stage: Equatable {
    case opening
    /// The hub: Moodi greets you; go squeeze, write a wish, check your mood or read the journal.
    case home
    case select
    case squeeze(MoodWorld)
    case wish(MoodWorld)
}

enum Language: String { case zh, en }

/// How easily a rock of the base counts as a squeeze.
enum Sensitivity: Int, CaseIterable {
    case gentle, normal, firm
    /// Multiplier on the detection threshold (lower = more sensitive).
    var thresholdScale: Double { [0.7, 1.0, 1.45][rawValue] }
}

@MainActor
final class AppModel: ObservableObject {
    private enum Key {
        static let language = "Moodium.Language"
        static let sensitivity = "Moodium.Sensitivity"
        static let muted = "Moodium.Muted"
        static let lastWorld = "Moodium.LastWorld"
        static let onboarded = "Moodium.Onboarded"
    }

    @Published var stage: Stage = .opening
    @Published var flash: Color?

    // Mood check (MoodCheckController): asked once before choosing a world, and again
    // after leaving one, so the two answers can be compared.
    @Published var moodCheck: MoodCheckRequest?
    /// Today's mood answer (kept until the day ends).
    @Published var preSample: MoodSample? {
        didSet { defaults.set(try? JSONEncoder().encode(preSample), forKey: "Moodium.TodayMood") }
    }
    /// Set when the pre check asked for a recommendation; the carousel tags that world.
    var recommendedWorld: MoodWorld? { preSample?.mood.recommendedWorld }

    @Published var language: Language { didSet { defaults.set(language.rawValue, forKey: Key.language) } }
    @Published var sensitivity: Sensitivity { didSet { defaults.set(sensitivity.rawValue, forKey: Key.sensitivity) } }
    @Published var muted: Bool { didSet { defaults.set(muted, forKey: Key.muted); AudioDirector.shared.muted = muted } }
    @Published var lastWorld: MoodWorld { didSet { defaults.set(lastWorld.rawValue, forKey: Key.lastWorld) } }

    private let defaults = UserDefaults.standard

    /// The language was chosen once; later launches skip the question.
    var onboarded: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }

    func goHome() { stage = .home }
    init() {
        let d = UserDefaults.standard
        language = Language(rawValue: d.string(forKey: Key.language) ?? "") ?? .zh
        sensitivity = Sensitivity(rawValue: d.integer(forKey: Key.sensitivity)) ?? .normal
        if d.object(forKey: Key.sensitivity) == nil { sensitivity = .normal }
        muted = d.bool(forKey: Key.muted)
        lastWorld = MoodWorld(rawValue: d.string(forKey: Key.lastWorld) ?? "") ?? .candy
        AudioDirector.shared.muted = muted
        if let data = d.data(forKey: "Moodium.TodayMood"), let sample = try? JSONDecoder().decode(MoodSample.self, from: data),
           Calendar.current.isDateInToday(sample.date) {
            preSample = sample
        }
    }

    /// Picks the Chinese or English copy for the current language.
    func t(_ zh: String, _ en: String) -> String { language == .zh ? zh : en }

    func enter(_ world: MoodWorld) {
        lastWorld = world
        flash = world.flashColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            self.stage = .squeeze(world)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.flash = nil }
        }
    }

    func backToSelect() { stage = .select }

    /// Leaving a world: after a finished rescue, ask "and now?" if the mood was checked before;
    /// otherwise just go back to the worlds.
    func leaveWorld(_ metrics: MoodVisitMetrics) {
        stage = .select
        if preSample != nil, metrics.completed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.moodCheck = .post(metrics) }
        } else {
            MoodLog.append(MoodVisit(world: metrics.world.rawValue, before: preSample, after: nil,
                                     seconds: metrics.seconds, squeezes: metrics.squeezes, mode: metrics.mode.rawValue))
        }
    }

    func recordPostSample(_ sample: MoodSample, metrics: MoodVisitMetrics) {
        MoodLog.append(MoodVisit(world: metrics.world.rawValue, before: preSample, after: sample,
                                 seconds: metrics.seconds, squeezes: metrics.squeezes, mode: metrics.mode.rawValue))
        // The latest answer becomes the "before" of the next visit.
        preSample = sample
    }

    func closeMoodCheck() { moodCheck = nil }

    /// A visit that went on to the wish chimes; finished (mood check after) when leaving them.
    private var wishVisit: MoodVisitMetrics?
    private var wishReturn: Stage = .home

    func openWish(_ world: MoodWorld, after visit: MoodVisitMetrics? = nil) {
        wishVisit = visit
        wishReturn = stage == .home ? .home : .select
        lastWorld = world
        stage = .wish(world)
    }

    func leaveWish() {
        if let visit = wishVisit {
            wishVisit = nil
            leaveWorld(visit)
        } else {
            stage = wishReturn
        }
    }
}
