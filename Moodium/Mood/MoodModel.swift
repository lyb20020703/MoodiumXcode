import SwiftUI

/// The five moods of the visionOS mood check (MoodClassifier.cs).
/// The plate is a valence (x: not great → pretty good) × arousal (y: tired → energized) disc.
enum MoodKind: String, Codable, CaseIterable, Identifiable {
    case happy, calm, neutral, low, tense
    var id: String { rawValue }

    /// Inside this radius the mood is "okay".
    static let neutralRadius = 0.22

    static func classify(_ p: CGPoint) -> MoodKind {
        let v = max(-1, min(1, p.x)), a = max(-1, min(1, p.y))
        if (v * v + a * a).squareRoot() < neutralRadius { return .neutral }
        if v >= 0 { return a >= 0 ? .happy : .calm }
        return a >= 0 ? .tense : .low
    }

    /// Where a quick tap on a mood puts Moodi on the plate.
    var preset: CGPoint {
        switch self {
        case .happy: return CGPoint(x: 0.6, y: 0.6)
        case .calm: return CGPoint(x: 0.6, y: -0.6)
        case .low: return CGPoint(x: -0.6, y: -0.6)
        case .tense: return CGPoint(x: -0.6, y: 0.6)
        case .neutral: return .zero
        }
    }

    /// MoodCheckPlate.Tint
    var tint: Color {
        switch self {
        case .happy: return Color(red: 1, green: 207 / 255, blue: 110 / 255)
        case .calm: return Color(red: 127 / 255, green: 221 / 255, blue: 190 / 255)
        case .low: return Color(red: 142 / 255, green: 168 / 255, blue: 230 / 255)
        case .tense: return Color(red: 240 / 255, green: 134 / 255, blue: 118 / 255)
        case .neutral: return Color(red: 228 / 255, green: 230 / 255, blue: 240 / 255)
        }
    }

    var moodiFace: String { "moodi_\(rawValue)" }
    var icon: String { "icon_mood_\(rawValue)" }

    /// Happy / low → Candy World, calm / tense / okay → Nature World.
    var recommendedWorld: MoodWorld { self == .happy || self == .low ? .candy : .nature }

    /// SqueezeTuning.Recommend
    var recommendedMode: SqueezeMode {
        switch self {
        case .happy, .low: return .rhythm
        case .calm, .tense: return .breath
        case .neutral: return .free
        }
    }

    /// "开心"
    func name(_ l: Language) -> String { MoodCopy.text("mood.\(rawValue)", l) }
    /// "愉快、有活力"
    func detail(_ l: Language) -> String { MoodCopy.text("mood.\(rawValue).desc", l) }
}

enum MoodComparison { case better, same, worse }

/// One mood check answer.
struct MoodSample: Codable, Equatable {
    var valence: Double
    var arousal: Double
    var mood: MoodKind
    var date = Date()

    init(_ p: CGPoint) {
        valence = Double(p.x); arousal = Double(p.y); mood = MoodKind.classify(p)
    }

    var point: CGPoint { CGPoint(x: valence, y: arousal) }

    /// MoodClassifier.Compare: did the mood move toward calm-and-good by at least 0.15?
    static func compare(before: MoodSample, after: MoodSample) -> MoodComparison {
        let target = CGPoint(x: 0.5, y: -0.1)
        func d(_ p: CGPoint) -> Double { Double(hypot(p.x - target.x, p.y - target.y)) }
        let improvement = d(before.point) - d(after.point)
        if improvement >= 0.15 { return .better }
        if improvement <= -0.15 { return .worse }
        return .same
    }
}

/// A finished visit, kept on this device only.
struct MoodVisit: Codable {
    var world: String
    var before: MoodSample?
    var after: MoodSample?
    var seconds: Double
    var squeezes: Int
    var mode: String
}

enum MoodLog {
    private static let key = "Moodium.MoodLog"

    static func append(_ visit: MoodVisit) {
        var all = load()
        all.append(visit)
        if all.count > 200 { all.removeFirst(all.count - 200) }
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func load() -> [MoodVisit] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([MoodVisit].self, from: data)) ?? []
    }
}

/// MoodCheckCopy.cs, with the sticker / bag lines reworded for the phone.
enum MoodCopy {
    static let table: [String: (String, String)] = [
        "plate.title.pre": ("你现在的心情怎么样？", "How are you feeling right now?"),
        "plate.title.post": ("现在呢？", "And now?"),
        "plate.hint": ("拖动 Moodi，或点选一个心情", "Drag Moodi, or tap a mood"),
        "axis.up": ("精力充沛", "Energized"),
        "axis.down": ("有点累", "Tired"),
        "axis.left": ("不太好", "Not great"),
        "axis.right": ("还不错", "Pretty good"),
        "mood.happy": ("开心", "Happy"),
        "mood.calm": ("平静", "Calm"),
        "mood.neutral": ("一般", "Okay"),
        "mood.low": ("低落", "Low"),
        "mood.tense": ("烦躁", "Tense"),
        "mood.happy.desc": ("愉快、有活力", "cheerful, energetic"),
        "mood.calm.desc": ("放松、安稳", "relaxed, settled"),
        "mood.neutral.desc": ("说不上好坏", "somewhere in between"),
        "mood.low.desc": ("有点累、提不起劲", "tired, a bit down"),
        "mood.tense.desc": ("紧张、有压力", "stressed, on edge"),
        "confirm.title": ("你现在感觉{mood}，对吗？", "So you're feeling {mood}?"),
        "confirm.yes": ("是的", "Yes"),
        "confirm.adjust": ("再调整", "Adjust"),
        "skip": ("跳过", "Skip"),
        "rec.happy": ("好心情，值得多留一会儿", "A good mood is worth keeping"),
        "rec.calm": ("这份平静很珍贵，慢慢待一会儿", "This calm is worth keeping"),
        "rec.neutral": ("两个世界都适合，先随意走走", "Either world works. Start anywhere"),
        "rec.low": ("给自己一点甜，轻轻捏一捏", "A little sweetness might help"),
        "rec.tense": ("跟着呼吸，慢慢放松下来", "Breathe slowly and let it ease"),
        "rec.today": ("现在：{mood}", "Now: {mood}"),
        "rec.other": ("也可以去{world}", "Or try {world}"),
        "rec.cta": ("去{world}", "Go to {world}"),
        "rec.retry": ("重新记录", "Check again"),
        "rec.short.happy": ("让好心情多留一会儿", "Make a good mood last"),
        "rec.short.calm": ("把这份平静带进自然世界", "Take this calm into Nature World"),
        "rec.short.neutral": ("先去自然世界走走", "Maybe start with Nature World"),
        "rec.short.low": ("给自己一点甜", "A little sweetness might help"),
        "rec.short.tense": ("去自然世界慢慢呼吸", "Breathe slowly in Nature World"),
        "rec.mode": ("推荐玩法：{mode}", "Suggested mode: {mode}"),
        "tag.pick": ("Moodi 推荐", "Moodi's pick"),
        "compare.kicker": ("在{world}待了一会儿之后", "After some time in {world}"),
        "compare.better": ("感觉轻松了一些", "A little lighter now"),
        "compare.same": ("谢谢你陪自己待了一会儿", "Thanks for spending a moment with yourself"),
        "compare.worse": ("没关系，有些日子就是这样。想再待一会儿也可以", "That's okay. Some days are like that. Stay a little longer if you like"),
        "compare.before": ("进入前", "Before"),
        "compare.now": ("现在", "Now"),
        "compare.time": ("停留时长", "Time"),
        "compare.squeezes": ("按压次数", "Squeezes"),
        "compare.privacy": ("记录仅保存在本机", "Saved only on this device"),
        "compare.continue": ("继续", "Continue"),
    ]

    static func text(_ key: String, _ l: Language, _ replacements: [String: String] = [:]) -> String {
        guard let pair = table[key] else { return key }
        var s = l == .zh ? pair.0 : pair.1
        for (k, v) in replacements { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s
    }
}
