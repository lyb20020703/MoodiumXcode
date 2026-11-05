import SwiftUI

/// Fireworks for the iPhone Duo tabletop sky: each squeeze sends a spark rocket up from
/// Moodi on the bottom half, across the fold, and it bursts in the top half.
@MainActor
final class FireworksShow: ObservableObject {
    enum Shape { case sphere, ring, heart, double }

    fileprivate struct Spark {
        var velocity: CGVector
        var color: Color
        var size: CGFloat
        var phase: Double
    }

    fileprivate struct Rocket {
        var start: CGPoint
        var apex: CGPoint
        var launch: Double
        var rise: Double
        var life: Double
        var color: Color
        var sparks: [Spark]
        var glitter: Bool
        var end: Double { launch + rise + life }
    }

    /// True when nothing is in the air, so the sky stops redrawing.
    @Published private(set) var idle = true
    private var rockets: [Rocket] = []
    private var palette: [Color] = [.white]
    private var glitterImage = "fx_twinkle"

    private static let drag = 2.4                 // per second; sparks slow down quickly
    private static let gravity: CGFloat = 70      // gentle droop after the burst

    func configure(world: MoodWorld) {
        switch world {
        case .candy:
            palette = [Color(hex: 0xFFB3D9), Color(hex: 0xD9C2FF), Color(hex: 0xFFE9A8), Color(hex: 0xBFF3E0), Color(hex: 0xFF8FC4)]
            glitterImage = "fx_star"
        case .nature:
            palette = [Color(hex: 0xC6F2A6), Color(hex: 0xFFE08A), Color(hex: 0xA8E4FF), Color(hex: 0xFFC9A8), Color(hex: 0xE9FFD6)]
            glitterImage = "fx_twinkle"
        }
    }

    /// One rocket from `start` into `sky`. `power` 0…1.3 sets the burst size, `reach` 0…1 how high it climbs.
    func launch(from start: CGPoint, sky: CGRect, reach: Double, power: Double, shape: Shape = .sphere, delay: Double = 0) {
        let now = Date().timeIntervalSinceReferenceDate + delay
        rockets.removeAll { $0.end < now - delay }
        // keep the sky readable: squeezes add at most a handful of rockets at once (scripted bursts always fly)
        if delay == 0, rockets.filter({ $0.launch + $0.rise > now }).count >= 5 { return }

        let highest = sky.minY + sky.height * (0.16 + 0.34 * (1 - reach))
        let lowest = sky.maxY - sky.height * 0.32
        let apexY = CGFloat.random(in: min(highest, lowest)...max(highest, lowest))
        let drift = CGFloat.random(in: -0.28...0.28) * sky.width
        let apexX = min(max(start.x + drift, sky.minX + sky.width * 0.14), sky.maxX - sky.width * 0.14)

        let radius = sky.height * CGFloat(0.13 + 0.12 * power)    // how far the sparks spread
        let speed = radius * CGFloat(Self.drag)
        let color = palette.randomElement() ?? .white
        let accent = palette.randomElement() ?? .white
        var sparks: [Spark] = []
        let count = Int(28 + 30 * power)
        for k in 0..<count {
            let a = CGFloat(Double(k) / Double(count) * 2 * .pi + Double.random(in: -0.05...0.05))
            var v: CGVector
            switch shape {
            case .sphere:
                let s = speed * CGFloat.random(in: 0.55...1.05)
                v = CGVector(dx: cos(a) * s, dy: sin(a) * s)
            case .ring:
                v = CGVector(dx: cos(a) * speed, dy: sin(a) * speed)
            case .double:
                let s = speed * (k % 2 == 0 ? 1 : 0.55)
                v = CGVector(dx: cos(a) * s, dy: sin(a) * s)
            case .heart:
                // classic heart curve, normalised to ~1, pointing up on screen
                let x = 16 * pow(sin(a), 3)
                let y = 13 * cos(a) - 5 * cos(2 * a) - 2 * cos(3 * a) - cos(4 * a)
                v = CGVector(dx: x / 17 * speed, dy: -y / 17 * speed)
            }
            let c = (shape == .double && k % 2 == 1) || Double.random(in: 0...1) < 0.25 ? accent : color
            sparks.append(Spark(velocity: v, color: c, size: CGFloat.random(in: 2.2...3.6), phase: Double.random(in: 0...6)))
        }
        rockets.append(Rocket(start: start, apex: CGPoint(x: apexX, y: apexY), launch: now,
                              rise: Double.random(in: 0.75...0.95), life: 1.5 + 0.3 * power,
                              color: color, sparks: sparks, glitter: power > 0.9))
        idle = false
        let end = rockets.map(\.end).max() ?? now
        DispatchQueue.main.asyncAfter(deadline: .now() + (end - Date().timeIntervalSinceReferenceDate) + 0.1) { [weak self] in
            guard let self else { return }
            if (self.rockets.map(\.end).max() ?? 0) < Date().timeIntervalSinceReferenceDate { self.idle = true }
        }
    }

    // MARK: Drawing

    fileprivate func draw(_ g: inout GraphicsContext, now: Double) {
        g.blendMode = .plusLighter
        let glitter = g.resolve(Image(asset: glitterImage).renderingMode(.template))
        for r in rockets where now >= r.launch && now <= r.end {
            let t = now - r.launch
            if t < r.rise {
                drawRise(&g, r, t)
            } else {
                drawBurst(&g, r, t - r.rise, glitter: glitter)
            }
        }
    }

    private func risePoint(_ r: Rocket, _ t: Double) -> CGPoint {
        let u = max(0, min(1, t / r.rise))
        let e = 1 - (1 - u) * (1 - u)     // ease out: slows as it reaches the top
        let wobble = sin(u * 9) * 3 * (1 - u)
        return CGPoint(x: r.start.x + (r.apex.x - r.start.x) * e + wobble,
                       y: r.start.y + (r.apex.y - r.start.y) * e)
    }

    private func drawRise(_ g: inout GraphicsContext, _ r: Rocket, _ t: Double) {
        for k in 0..<8 {
            let p = risePoint(r, t - Double(k) * 0.025)
            let a = 1 - Double(k) / 8
            let s = 3.2 * CGFloat(a) + 0.8
            g.fill(Path(ellipseIn: CGRect(x: p.x - s, y: p.y - s, width: 2 * s, height: 2 * s)),
                   with: .color((k == 0 ? Color.white : r.color).opacity(0.9 * a)))
        }
        let head = risePoint(r, t)
        g.fill(Path(ellipseIn: CGRect(x: head.x - 9, y: head.y - 9, width: 18, height: 18)), with: .color(r.color.opacity(0.25)))
    }

    private func sparkPoint(_ s: Spark, _ apex: CGPoint, _ t: Double) -> CGPoint {
        let k = Self.drag
        let f = CGFloat((1 - exp(-k * t)) / k)
        return CGPoint(x: apex.x + s.velocity.dx * f,
                       y: apex.y + s.velocity.dy * f + 0.5 * Self.gravity * CGFloat(t * t))
    }

    private func drawBurst(_ g: inout GraphicsContext, _ r: Rocket, _ t: Double, glitter: GraphicsContext.ResolvedImage) {
        // flash
        if t < 0.3 {
            let a = 1 - t / 0.3
            let s = 26 + 60 * CGFloat(t / 0.3)
            g.fill(Path(ellipseIn: CGRect(x: r.apex.x - s, y: r.apex.y - s, width: 2 * s, height: 2 * s)),
                   with: .radialGradient(Gradient(colors: [.white.opacity(0.75 * a), r.color.opacity(0.35 * a), .clear]),
                                         center: r.apex, startRadius: 0, endRadius: s))
        }
        let fade = max(0, 1 - t / r.life)
        for (i, s) in r.sparks.enumerated() {
            // late twinkle
            let flicker = t > r.life * 0.55 ? 0.55 + 0.45 * sin(t * 26 + s.phase) : 1
            let alpha = pow(fade, 1.4) * flicker
            guard alpha > 0.02 else { continue }
            // soft halo, then a short streak behind each spark
            let head = sparkPoint(s, r.apex, t)
            let halo = s.size * 3
            g.fill(Path(ellipseIn: CGRect(x: head.x - halo, y: head.y - halo, width: 2 * halo, height: 2 * halo)),
                   with: .color(s.color.opacity(alpha * 0.22)))
            for k in 0..<3 {
                let p = sparkPoint(s, r.apex, max(0, t - Double(k) * 0.045))
                let size = s.size * (1 - CGFloat(k) * 0.28) * CGFloat(0.6 + 0.4 * fade)
                g.fill(Path(ellipseIn: CGRect(x: p.x - size, y: p.y - size, width: 2 * size, height: 2 * size)),
                       with: .color((k == 0 && t < 0.25 ? Color.white : s.color).opacity(alpha * (1 - Double(k) * 0.3))))
            }
            // a few glittering stars in the big bursts
            if r.glitter, i % 6 == 0 {
                let p = sparkPoint(s, r.apex, t)
                var img = glitter
                img.shading = .color(s.color.opacity(alpha))
                let w = 11 * CGFloat(0.5 + 0.5 * fade)
                g.draw(img, in: CGRect(x: p.x - w / 2, y: p.y - w / 2, width: w, height: w))
            }
        }
    }
}

/// Full-screen, non-interactive layer that draws the fireworks.
struct FireworksLayer: View {
    @ObservedObject var show: FireworksShow

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: show.idle)) { context in
            Canvas { g, _ in show.draw(&g, now: context.date.timeIntervalSinceReferenceDate) }
        }
        .allowsHitTesting(false)
    }
}

/// The top half in tabletop posture: the world's sky, darker toward the top so the
/// fireworks stand out, with a few stars; and a soft shadow over the fold itself.
struct TabletopSky: View {
    let world: MoodWorld
    let fold: TabletopFold

    /// How far below the fold the sky keeps fading out over the stage.
    private let feather: CGFloat = 70

    var body: some View {
        // Night at the top, the world's own colours lower down, then a long fade across the
        // fold into the stage's sky (drawn under this), so the two halves read as one scene.
        let height = fold.band.maxY + feather
        // fully opaque down to where the stage starts drawing (the top of the band), so nothing
        // dark shows through; the fade happens only over the stage's own sky
        let fadeStart = fold.band.minY / height
        ZStack(alignment: .topLeading) {
            Color.clear.overlay {
                ZStack {
                    Palette.ink
                    if let image = Res.image(world.backdrop) {
                        Image(uiImage: image).resizable().scaledToFill().blur(radius: 3)
                    }
                    LinearGradient(stops: [.init(color: Palette.ink.opacity(0.95), location: 0),
                                           .init(color: Palette.ink.opacity(0.7), location: 0.45),
                                           .init(color: Palette.ink.opacity(0.12), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                    TwinkleField(count: 30, color: .white.opacity(0.8))
                }
            }
            .clipped()
            .frame(width: fold.top.width, height: height)
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: fadeStart),
                                       .init(color: .black.opacity(0.5), location: fadeStart + (1 - fadeStart) * 0.45),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .offset(x: fold.top.minX, y: fold.top.minY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
