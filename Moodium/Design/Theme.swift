import SwiftUI

/// Colours from the visionOS UI refresh tokens (ui-refresh.tokens.json).
enum Palette {
    static let ink = Color(hex: 0x1E1A28)
    static let smoke = Color(hex: 0x2B2238)
    static let candy = Color(hex: 0xF27DB6)
    static let nature = Color(hex: 0x55C47F)
    static let lavender = Color(hex: 0xB79CF2)
    static let textMuted = Color.white.opacity(0.74)
    static let labelUnselected = Color.white.opacity(0.82)
}

extension Font {
    /// Rounded system face; the Unity project's Alibaba PuHuiTi only ships as TMP SDF atlases.
    static func moodium(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Liquid glass

/// The glass surface used across the visionOS UI: blur, a soft white sheen and a bright rim.
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
                    shape.fill(LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.04), .white.opacity(0.10)],
                                              startPoint: .top, endPoint: .bottom))
                    if let tint { shape.fill(tint.opacity(tintAmount)) }
                }
            }
            .overlay {
                shape.stroke(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.12), .white.opacity(0.42)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            .shadow(color: .black.opacity(shadow ? 0.28 : 0), radius: 14, y: 6)
    }
}

extension View {
    func glass(_ shape: some Shape = Capsule(), tint: Color? = nil, amount: Double = 0.18, shadow: Bool = true) -> some View {
        modifier(GlassSurface(shape: AnyShape(shape), tint: tint, tintAmount: amount, shadow: shadow))
    }
}

/// Glass capsule button with a gentle press.
struct GlassButtonStyle: ButtonStyle {
    var tint: Color? = nil
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.moodium(17, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background {
                if prominent, let tint {
                    Capsule().fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                }
            }
            .glass(tint: prominent ? nil : tint, amount: 0.22)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Round glass icon button (back, settings, sound).
struct GlassIconButton: View {
    let symbol: String
    var size: CGFloat = 46
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
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
        let sprite = configuration.isPressed ? "opening_btn_bg_pressed" : (highlighted ? "opening_btn_bg_gaze" : "opening_btn_bg_idle")
        return ZStack {
            Image(asset: sprite).resizable().interpolation(.high)
            configuration.label
                .font(.moodium(22, .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .offset(y: -2)
        }
        .frame(width: 200, height: 113)
        .scaleEffect(configuration.isPressed ? 0.96 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Backdrop

/// Dark smoky room with slow coloured light pools, like the visionOS preview boards.
struct MoodBackdrop: View {
    var colors: [Color] = [Color(hex: 0x8E7B6A), Palette.lavender, Color(hex: 0x4E7A5A)]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.ink))
                let anchors: [(CGFloat, CGFloat, CGFloat, Double)] = [(0.18, 0.28, 0.6, 0.22), (0.78, 0.72, 0.55, 0.18), (0.88, 0.2, 0.45, 0.14)]
                for (i, color) in colors.enumerated() where i < anchors.count {
                    let a = anchors[i]
                    let x = size.width * (a.0 + 0.05 * CGFloat(sin(t * 0.11 + Double(i) * 2.1)))
                    let y = size.height * (a.1 + 0.06 * CGFloat(cos(t * 0.09 + Double(i))))
                    let r = max(size.width, size.height) * a.2
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .radialGradient(Gradient(colors: [color.opacity(a.3), color.opacity(0)]),
                                                   center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
                }
                // Vignette keeps the edges deep so glass reads well.
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.55)]), center: c,
                                               startRadius: min(size.width, size.height) * 0.35, endRadius: max(size.width, size.height) * 0.75))
            }
        }
        .ignoresSafeArea()
    }
}

/// Small twinkling motes that drift over dark screens.
struct TwinkleField: View {
    var count = 28
    var color: Color = .white

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
