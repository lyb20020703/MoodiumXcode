import SwiftUI
import UIKit

/// The two worlds shared with the visionOS version, with their look and assets.
enum MoodWorld: String, CaseIterable, Identifiable, Hashable {
    case candy, nature

    var id: String { rawValue }
    var index: Int { self == .candy ? 0 : 1 }
    static func at(_ index: Int) -> MoodWorld { index == 0 ? .candy : .nature }

    func name(_ l: Language) -> String {
        switch self {
        case .candy: return l == .zh ? "糖果世界" : "Candy World"
        case .nature: return l == .zh ? "自然世界" : "Nature World"
        }
    }

    func tagline(_ l: Language) -> String {
        switch self {
        case .candy: return l == .zh ? "软软甜甜，把紧绷一点点捏散" : "Soft and sweet, squeeze the tension away"
        case .nature: return l == .zh ? "在萤火草地里，慢慢呼吸" : "Breathe slowly in the firefly meadow"
        }
    }

    func enterLabel(_ l: Language) -> String {
        switch self {
        case .candy: return l == .zh ? "滑动进入糖果世界" : "Slide into Candy World"
        case .nature: return l == .zh ? "滑动进入自然世界" : "Slide into Nature World"
        }
    }

    func moodiLine(_ l: Language) -> String {
        switch self {
        case .candy: return l == .zh ? "这里软软甜甜的～" : "It's so soft and sweet here!"
        case .nature: return l == .zh ? "跟我去森林里深呼吸吧" : "Come take a deep breath with me"
        }
    }

    // MARK: Colour (from the visionOS UI tokens and GlassSlideToEnter)

    var accent: Color { self == .candy ? Color(hex: 0xF27DB6) : Color(hex: 0x55C47F) }
    var uiAccent: UIColor { UIColor(accent) }
    var tint: Color { self == .candy ? Color(red: 1, green: 0.67, blue: 0.84) : Color(red: 0.67, green: 0.9, blue: 0.75) }
    var glow: Color { self == .candy ? Color(red: 1, green: 0.55, blue: 0.78) : Color(red: 0.47, green: 0.86, blue: 0.59) }
    var fill: Color { self == .candy ? Color(red: 0.96, green: 0.51, blue: 0.75) : Color(red: 0.38, green: 0.77, blue: 0.47) }
    var knobStops: [Color] {
        self == .candy
            ? [Color(hex: 0xFFF0F7), Color(hex: 0xFFB3D4), Color(hex: 0xE879B4)]
            : [Color(hex: 0xF0FFF4), Color(hex: 0xAEE8C2), Color(hex: 0x4FB874)]
    }
    var flashColor: Color { self == .candy ? Color(hex: 0xFFE3F0) : Color(hex: 0xE6FFEC) }
    /// Secondary glow used in backdrops.
    var mist: Color { self == .candy ? Color(hex: 0xB79CF2) : Color(hex: 0x7FD3E8) }

    // MARK: Assets

    var panorama: String { self == .candy ? "pano_candy" : "pano_nature" }
    var backdrop: String { self == .candy ? "backdrop_candy" : "backdrop_nature" }
    var softModel: String { self == .candy ? "CandySoft" : "NatureSoft" }
    var islandModel: String { self == .candy ? "CandyWorldUI" : "NatureWorldUI" }
    var icon: String { self == .candy ? "world_icon_candy" : "world_icon_nature" }
    var bgm: String { self == .candy ? "bgm_candy" : "bgm_nature" }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// Finds bundled files whether Xcode copied them flat or kept the folder.
enum Res {
    static func url(_ name: String, _ ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        for dir in ["Resources/Models", "Resources/World", "Resources/Audio", "Resources/Voice", "Resources/Video",
                    "Models", "World", "Audio", "Voice", "Video"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: dir) { return url }
        }
        return nil
    }

    private static let images = NSCache<NSString, UIImage>()

    /// Loads (and caches) a bundled image file such as a panorama.
    static func image(_ name: String, _ ext: String = "jpg") -> UIImage? {
        if let cached = images.object(forKey: name as NSString) { return cached }
        let image = url(name, ext).flatMap { UIImage(contentsOfFile: $0.path) } ?? UIImage(named: name)
        if let image { images.setObject(image, forKey: name as NSString) }
        return image
    }
}
