import SwiftUI

/// Colours from WishChime.cs / WishInkMesh.cs.
struct WishStyle {
    let paper: Color
    let ink: Color
    let glow: Color
    let accent: Color

    static func of(_ world: MoodWorld) -> WishStyle {
        world == .candy
            ? WishStyle(paper: Color(hex: 0xFFE6F0), ink: Color(hex: 0xC93D78), glow: Color(hex: 0xFF78B4), accent: world.accent)
            : WishStyle(paper: Color(hex: 0xC9A574), ink: Color(hex: 0x3E2A16), glow: Color(hex: 0xFFE98C), accent: world.accent)
    }
}

/// The wish strip: 8.5 × 27.5 proportions, gently curled top and bottom edges.
struct PaperShape: Shape {
    func path(in r: CGRect) -> Path {
        let dip = r.width * 0.09
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.minY + dip * 2))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - dip))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - dip), control: CGPoint(x: r.midX, y: r.maxY + dip))
        p.closeSubpath()
        return p
    }
}

/// Paper + ink. Widths follow WishInkMesh: ink 1.6 mm and glow 4.8 mm on a 34 mm wide strip.
struct WishPaperView: View {
    let world: MoodWorld
    var strokes: [WishStroke]
    var active: WishStroke? = nil
    var tip: CGPoint? = nil
    var preset = false
    var inkAlpha: Double = 1
    var cursor: CGPoint? = nil
    var cursorPulse: Double = 0

    var body: some View {
        let style = WishStyle.of(world)
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                PaperShape().fill(style.paper)
                    .shadow(color: .black.opacity(0.22), radius: size.width * 0.06, y: size.width * 0.03)
                // a faint sheen down the curl
                PaperShape().fill(LinearGradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.06)],
                                                 startPoint: .leading, endPoint: .trailing))
                if world == .nature {
                    Image(asset: "fx_leaf1").resizable().scaledToFit()
                        .frame(width: size.width * 0.26)
                        .colorMultiply(Color(hex: 0x6FCF8E))
                        .rotationEffect(.degrees(-35))
                        .position(x: size.width * 0.18, y: size.height * 0.92)
                }
                Canvas { ctx, s in
                    let w = s.width
                    let inkW = w * 0.047 * (preset ? WishPresets.inkWidth : 1)
                    let glowW = w * 0.141 * (preset ? WishPresets.glowWidth : 1)
                    var all = strokes
                    if var a = active {
                        if let tip { a.append([Float(tip.x), Float(tip.y)]) }
                        all.append(a)
                    }
                    var path = Path()
                    for stroke in all where !stroke.isEmpty {
                        let pts = stroke.map { CGPoint(x: CGFloat($0[0]) * s.width, y: (1 - CGFloat($0[1])) * s.height) }
                        path.move(to: pts[0])
                        if pts.count == 1 { path.addLine(to: CGPoint(x: pts[0].x + 0.1, y: pts[0].y)) }
                        for k in 1..<max(1, pts.count) {
                            // midpoint quad curves keep the line smooth between sparse points
                            let mid = CGPoint(x: (pts[k - 1].x + pts[k].x) / 2, y: (pts[k - 1].y + pts[k].y) / 2)
                            if k == 1 { path.addLine(to: mid) } else { path.addQuadCurve(to: mid, control: pts[k - 1]) }
                            if k == pts.count - 1 { path.addLine(to: pts[k]) }
                        }
                    }
                    ctx.opacity = inkAlpha
                    ctx.stroke(path, with: .color(style.glow.opacity(0.35)), style: StrokeStyle(lineWidth: glowW, lineCap: .round, lineJoin: .round))
                    ctx.stroke(path, with: .color(style.ink), style: StrokeStyle(lineWidth: inkW, lineCap: .round, lineJoin: .round))
                }
                .clipShape(PaperShape())
                if let c = cursor {
                    Circle().fill(style.glow)
                        .frame(width: size.width * (0.09 + 0.06 * cursorPulse), height: size.width * (0.09 + 0.06 * cursorPulse))
                        .shadow(color: style.glow, radius: 6)
                        .overlay(Circle().fill(.white).frame(width: size.width * 0.04))
                        .position(x: c.x * size.width, y: (1 - c.y) * size.height)
                        .allowsHitTesting(false)
                }
            }
        }
        .aspectRatio(8.5 / 27.5, contentMode: .fit)
    }
}

/// A hung chime: the rendered bell (from WishChime_Candy / _Nature) with its paper strip below.
/// `width` is the bell image width; the strip is 46 % of it, as in the model.
struct HangingChime: View {
    let world: MoodWorld
    let record: WishRecord
    let width: CGFloat

    var body: some View {
        let stripW = width * 166 / 360
        VStack(spacing: -width * 0.03) {
            Image(asset: "chime_bell_\(world.rawValue)").resizable()
                .frame(width: width, height: width * 450 / 360)
            WishPaperView(world: world, strokes: record.strokes, preset: record.preset != nil)
                .frame(width: stripW)
        }
    }
}
