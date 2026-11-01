import Foundation
import CoreGraphics

/// A stroke is a list of [u, v] points on the paper (u: 0 left → 1 right, v: 0 bottom → 1 top),
/// exactly the handwriting format of the visionOS WishChimeRecord, so a wish written here
/// could be read there and the other way round.
typealias WishStroke = [[Float]]

/// One hung wish (WishChimeStore.cs → WishChimeRecord).
struct WishRecord: Codable, Identifiable, Equatable {
    var id: String
    var world: String
    var folder: String = "phone"
    var createdAt: String
    var layer: Int = 0
    var position: [Float] = [0, 0, 0]
    var yaw: Float = 0
    var strokes: [WishStroke]
    var preset: String?
}

struct WishDocument: Codable {
    var version = 1
    var chimes: [WishRecord] = []
}

/// wish_chimes.json in Application Support, written atomically (temp file + replace).
enum WishStore {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("wish_chimes.json")
    }

    static func load() -> [WishRecord] {
        guard let data = try? Data(contentsOf: url),
              let doc = try? JSONDecoder().decode(WishDocument.self, from: data), doc.version == 1 else { return [] }
        return doc.chimes.filter { canRelease($0.strokes) }
    }

    @discardableResult
    static func append(_ record: WishRecord) -> Bool {
        var doc = WishDocument(chimes: load())
        doc.chimes.append(record)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(doc).write(to: url, options: .atomic)
            return true
        } catch {
            print("[Wish Chime] Save failed: \(error)")
            return false
        }
    }

    static func canRelease(_ strokes: [WishStroke]) -> Bool { strokes.contains { $0.count >= 2 } }

    /// WishChimeStore.AddPoint: half-way smoothing toward the finger, and a new point only after
    /// ~1.5 mm of travel on the (2.5× enlarged) 3.4 × 11 cm paper.
    static func addPoint(_ stroke: inout WishStroke, _ uv: CGPoint, paperScale: Float = 2.5) -> Bool {
        var u = Float(uv.x), v = Float(uv.y)
        if let last = stroke.last {
            u = (last[0] + u) / 2; v = (last[1] + v) / 2
            let dx = (u - last[0]) * 0.034 * paperScale, dy = (v - last[1]) * 0.11 * paperScale
            if (dx * dx + dy * dy).squareRoot() < 0.0015 { return false }
        }
        stroke.append([min(1, max(0, u)), min(1, max(0, v))])
        return true
    }

    static let maxPoints = 4000
    static let maxStrokePoints = 74
}

// MARK: - Preset wishes (WishPresetLibrary)

struct WishPreset: Codable {
    var id: String
    var lang: String
    var text: String
    var chip: String
    var kinds: [Int]
    var strokes: [WishStroke]
}

struct WishPresetDocument: Codable {
    var version: Int
    var paperCm: [Float]
    var presets: [WishPreset]
}

enum WishPresets {
    /// Chip order, top to bottom; "write_own" comes last.
    static let ids = ["peace_joy", "happy", "good_vibes", "stay_well", "let_go"]
    static let writeOwn = "write_own"
    /// Presets draw thinner ink than a finger: the glyphs are denser than handwriting.
    static let inkWidth: CGFloat = 0.7, glowWidth: CGFloat = 0.5

    static let document: WishPresetDocument? = {
        guard let url = Res.url("wish_presets", "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WishPresetDocument.self, from: data)
    }()

    static func find(_ id: String, _ language: Language) -> WishPreset? {
        document?.presets.first { $0.id == id && $0.lang == language.rawValue }
    }
}

/// WishWritingTimeline.cs: replays a preset stroke by stroke in about 2.2–3.4 s, with short
/// pauses between strokes and longer ones between characters, and an eased pen speed.
struct WishTimeline {
    static let paperW: Float = 8.5, paperH: Float = 27.5
    static let strokeGap: Float = 0.03, glyphGap: Float = 0.14, minStroke: Float = 0.05
    static let baseSeconds: Float = 1.4, cmPerSecond: Float = 45, minSeconds: Float = 2.2, maxSeconds: Float = 3.4
    static let ease: Float = 0.8

    struct Group { var first = 0, count = 0; var length: Float = 0, gap: Float = 0, start: Float = 0, duration: Float = 0 }
    struct Frame { var done: Int; var partial: WishStroke?; var tip: CGPoint? }

    let strokes: [WishStroke]
    private(set) var groups: [Group] = []
    private(set) var total: Float = 0

    init(strokes: [WishStroke], kinds: [Int]) {
        self.strokes = strokes
        var pen: Float = 0, pauses: Float = 0
        for (i, s) in strokes.enumerated() {
            let kind = i < kinds.count ? kinds[i] : 1
            if i == 0 || kind != 0 {
                let gap: Float = i == 0 ? 0 : kind == 2 ? Self.glyphGap : Self.strokeGap
                groups.append(Group(first: i, gap: gap))
                pauses += gap
            }
            let len = Self.length(s)
            groups[groups.count - 1].count += 1
            groups[groups.count - 1].length += len
            pen += len
        }
        let target = min(Self.maxSeconds, max(Self.minSeconds, Self.baseSeconds + pen / Self.cmPerSecond))
        let penTime = max(target - pauses, Float(groups.count) * Self.minStroke)
        var raw: Float = 0
        for i in groups.indices {
            groups[i].duration = max(Self.minStroke, groups[i].length / max(pen, 1e-6) * penTime)
            raw += groups[i].gap + groups[i].duration
        }
        let scale = raw > target ? target / raw : 1
        var t: Float = 0
        for i in groups.indices {
            groups[i].gap *= scale; groups[i].duration *= scale
            t += groups[i].gap
            groups[i].start = t
            t += groups[i].duration
        }
        total = t
    }

    static func segment(_ a: [Float], _ b: [Float]) -> Float {
        let dx = (b[0] - a[0]) * paperW, dy = (b[1] - a[1]) * paperH
        return (dx * dx + dy * dy).squareRoot()
    }

    static func length(_ s: WishStroke) -> Float {
        var d: Float = 0
        for i in 1..<max(1, s.count) { d += segment(s[i - 1], s[i]) }
        return d
    }

    static func easeAt(_ s: Float) -> Float {
        let c = min(1, max(0, s))
        return c - ease * sin(2 * .pi * c) / (2 * .pi)
    }

    func sample(_ time: Float) -> Frame {
        for g in groups {
            if time < g.start { return Frame(done: g.first, partial: nil, tip: nil) }
            if time >= g.start + g.duration { continue }
            var d = Self.easeAt((time - g.start) / g.duration) * g.length
            for i in g.first..<(g.first + g.count) {
                let s = strokes[i]
                for j in 1..<max(1, s.count) {
                    let seg = Self.segment(s[j - 1], s[j])
                    if d <= seg {
                        let f = seg > 0 ? d / seg : 0
                        let tip = CGPoint(x: CGFloat(s[j - 1][0] + (s[j][0] - s[j - 1][0]) * f),
                                          y: CGFloat(s[j - 1][1] + (s[j][1] - s[j - 1][1]) * f))
                        return Frame(done: i, partial: Array(s[0..<j]), tip: tip)
                    }
                    d -= seg
                }
            }
            return Frame(done: g.first + g.count, partial: nil, tip: nil)
        }
        return Frame(done: strokes.count, partial: nil, tip: nil)
    }
}
