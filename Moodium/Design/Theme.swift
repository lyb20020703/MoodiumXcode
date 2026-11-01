import SwiftUI

/// Soft lavender look: light gradient rooms, frosted white cards, deep plum text,
/// pastel iridescent glows (pink → lilac → sky → mint).
enum Palette {
    /// Primary text and dark pills.
    static let ink = Color(hex: 0x2B2150)
    /// Light panel tint (was the smoky purple of the dark theme).
    static let smoke = Color(hex: 0xF3EEFC)
    static let candy = Color(hex: 0xF27DB6)
    static let nature = Color(hex: 0x55C47F)
    static let lavender = Color(hex: 0xB79CF2)
    static let lilac = Color(hex: 0x9C82EE)
    static let blush = Color(hex: 0xF7A8CF)
    static let sky = Color(hex: 0x9CC7F5)
    static let mint = Color(hex: 0x9BE3C7)
    static let textMuted = Color(hex: 0x2B2150).opacity(0.58)
    static let labelUnselected = Color(hex: 0x2B2150).opacity(0.62)
    /// Room background, top to bottom.
    static let roomTop = Color(hex: 0xF4EFFD)
    static let roomMid = Color(hex: 0xE6DBF8)
    static let roomBottom = Color(hex: 0xF8E9F3)
    static let iridescent: [Color] = [Color(hex: 0xF7A8CF), Color(hex: 0xB79CF2), Color(hex: 0x9CC7F5), Color(hex: 0x9BE3C7), Color(hex: 0xF7A8CF)]
    static let shadow = Color(hex: 0x6B4FC8)
}

extension Font {
    /// Rounded system face; the Unity project's Alibaba PuHuiTi only ships as TMP SDF atlases.
    static func moodium(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Frosted cards

/// Frosted white card: blur, a milky white fill, a bright rim and a soft lilac shadow.
struct GlassSurface: ViewModifier {
    var shape: AnyShape
    var tint: Color?
    var tintAmount: Double = 0.18
    var shadow = true

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(.white.opacity(0.58))
                    if let tint { shape.fill(tint.opacity(tintAmount)) }
                    shape.fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .top, endPoint: .center))
                }
            }
            .overlay {
                shape.stroke(LinearGradient(colors: [.white, .white.opacity(0.35)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: Palette.shadow.opacity(shadow ? 0.16 : 0), radius: 18, y: 8)
    }
}

extension View {
    func glass(_ shape: some Shape = Capsule(), tint: Color? = nil, amount: Double = 0.18, shadow: Bool = true) -> some View {
        modifier(GlassSurface(shape: AnyShape(shape), tint: tint, tintAmount: amount, shadow: shadow))
    }
}

/// Pill button. Prominent = filled with the tint (white text); plain = frosted white (plum text).
struct GlassButtonStyle: ButtonStyle {
    var tint: Color? = nil
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.moodium(17, .semibold))
            .foregroundStyle(prominent ? .white : Palette.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background {
                if prominent {
                    let c = tint ?? Palette.ink
                    Capsule().fill(LinearGradient(colors: [c.opacity(0.95), c], startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)))
                        .shadow(color: c.opacity(0.4), radius: 12, y: 6)
                }
            }
            .modifier(OptionalGlass(on: !prominent, tint: tint))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct OptionalGlass: ViewModifier {
    var on: Bool
    var tint: Color?
    func body(content: Content) -> some View {
        if on { content.glass(tint: tint, amount: 0.12) } else { content }
    }
}

/// Round frosted icon button (back, settings, sound).
struct GlassIconButton: View {
    let symbol: String
    var size: CGFloat = 46
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: size, height: size)
        }
        .buttonStyle(IconPressStyle())
        .glass(Circle())
    }
}

private struct IconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

/// Opening-style pill: the exported visionOS glass sprite with a word on top.
struct OpeningPill: View {
    let title: String
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(OpeningPillStyle(highlighted: highlighted))
    }
}

private struct OpeningPillStyle: ButtonStyle {
    var highlighted: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.moodium(20, .bold))
            .foregroundStyle(highlighted ? .white : Palette.ink)
            .frame(width: 168, height: 58)
            .background {
                if highlighted {
                    Capsule().fill(LinearGradient(colors: [Palette.lilac, Color(hex: 0xC48BE8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: Palette.lilac.opacity(0.45), radius: 14, y: 6)
                }
            }
            .glass(shadow: !highlighted)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Backdrop

/// Light lavender room with slow pastel light pools drifting around.
struct MoodBackdrop: View {
    var colors: [Color] = [Palette.blush, Palette.lavender, Palette.sky]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [Palette.roomTop, Palette.roomMid, Palette.roomBottom]),
                                               startPoint: .zero, endPoint: CGPoint(x: size.width * 0.4, y: size.height)))
                let anchors: [(CGFloat, CGFloat, CGFloat, Double)] = [(0.12, 0.22, 0.42, 0.55), (0.82, 0.78, 0.5, 0.45), (0.9, 0.12, 0.38, 0.4), (0.45, 0.95, 0.4, 0.35)]
                let pool = colors + [Palette.mint]
                for (i, a) in anchors.enumerated() {
                    let color = pool[i % pool.count]
                    let x = size.width * (a.0 + 0.05 * CGFloat(sin(t * 0.11 + Double(i) * 2.1)))
                    let y = size.height * (a.1 + 0.06 * CGFloat(cos(t * 0.09 + Double(i))))
                    let r = max(size.width, size.height) * a.2
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .radialGradient(Gradient(colors: [color.opacity(a.3), color.opacity(0)]),
                                                   center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// A soft iridescent glow orb (the pastel blob behind Moodi).
struct IridescentOrb: View {
    var size: CGFloat
    var tint: Color? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: Palette.iridescent, center: .center, angle: .degrees(t * 12)))
                    .blur(radius: size * 0.12)
                    .opacity(0.85)
                if let tint {
                    Circle().fill(RadialGradient(colors: [tint.opacity(0.7), tint.opacity(0)], center: .center, startRadius: 0, endRadius: size * 0.5))
                }
                Circle().fill(RadialGradient(colors: [.white.opacity(0.85), .white.opacity(0)], center: UnitPoint(x: 0.42, y: 0.35),
                                             startRadius: 0, endRadius: size * 0.42))
            }
            .frame(width: size, height: size)
            .scaleEffect(1 + 0.025 * sin(t * 1.3))
        }
        .allowsHitTesting(false)
    }
}

/// Small twinkling motes that drift over the room.
struct TwinkleField: View {
    var count = 28
    var color: Color = Palette.lilac

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for i in 0..<count {
                    let seed = Double(i) * 12.9898
                    let fx = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let fy = (sin(seed * 1.7) * 23421.631).truncatingRemainder(dividingBy: 1)
                    let x = abs(fx) * size.width
                    let y = (abs(fy) * size.height - t * (6 + Double(i % 5) * 2)).truncatingRemainder(dividingBy: size.height)
                    let yy = y < 0 ? y + size.height : y
                    let tw = 0.5 + 0.5 * sin(t * (1.2 + Double(i % 7) * 0.3) + seed)
                    let r = 1.0 + 1.6 * tw
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: yy - r, width: r * 2, height: r * 2)),
                             with: .color(color.opacity(0.15 + 0.5 * tw)))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

extension Image {
    /// Loads from the asset catalog (or a loose bundle file) through UIImage.
    init(asset name: String) {
        if let image = UIImage(named: name) { self.init(uiImage: image) } else { self.init(name) }
    }
}
