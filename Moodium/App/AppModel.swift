import SwiftUI

enum Stage: Equatable {
    case opening
    case select
    case squeeze(MoodWorld)
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
        static let hasBase = "Moodium.HasBase"
        static let sensitivity = "Moodium.Sensitivity"
        static let muted = "Moodium.Muted"
        static let lastWorld = "Moodium.LastWorld"
    }

    @Published var stage: Stage = .opening
    @Published var flash: Color?

    @Published var language: Language { didSet { defaults.set(language.rawValue, forKey: Key.language) } }
    @Published var hasBase: Bool { didSet { defaults.set(hasBase, forKey: Key.hasBase) } }
    @Published var sensitivity: Sensitivity { didSet { defaults.set(sensitivity.rawValue, forKey: Key.sensitivity) } }
    @Published var muted: Bool { didSet { defaults.set(muted, forKey: Key.muted); AudioDirector.shared.muted = muted } }
    @Published var lastWorld: MoodWorld { didSet { defaults.set(lastWorld.rawValue, forKey: Key.lastWorld) } }

    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        language = Language(rawValue: d.string(forKey: Key.language) ?? "") ?? .zh
        hasBase = d.object(forKey: Key.hasBase) as? Bool ?? true
        sensitivity = Sensitivity(rawValue: d.integer(forKey: Key.sensitivity)) ?? .normal
        if d.object(forKey: Key.sensitivity) == nil { sensitivity = .normal }
        muted = d.bool(forKey: Key.muted)
        lastWorld = MoodWorld(rawValue: d.string(forKey: Key.lastWorld) ?? "") ?? .candy
        AudioDirector.shared.muted = muted
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
}
