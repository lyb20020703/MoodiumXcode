import SwiftUI

/// A full-screen light layer over the world (under the controls) that makes each mode felt,
/// not only shown on the ring:
/// - free: a warm glow wells up around the pillow while the bag is rocking;
/// - rhythm: the screen edges pulse softly on every beat, brighter on a good hit and with a streak;
/// - breath: the edges dim to a calm frame, and light rises from the pillow as you breathe in
///   and sinks back as you breathe out.
struct ModeAtmosphere: View {
    @ObservedObject var director: SqueezeDirector
    let world: MoodWorld
    /// Where the stage view starts inside this layer (the layer covers the whole screen when the
    /// iPhone Duo's fold splits it, so its dimmed edges are the screen's, not the fold).
    var stageOffset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let size = geo.size
                ZStack {
                    switch director.mode {
                    case .free: freeGlow(size)
                    case .rhythm: beatPulse(size, date: context.date)
                    case .breath: breathTide(size, date: context.date)
                    }
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .opacity(director.phase == .complete ? 0 : 1)
        .animation(.easeOut(duration: 0.6), value: director.phase)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where the light comes from: the pillow, or low in the middle until it is known.
    private func pillow(_ size: CGSize) -> CGPoint {
        if let r = director.jellyRect, r.width > 0 { return CGPoint(x: r.midX, y: r.midY + stageOffset) }
        return CGPoint(x: size.width / 2, y: stageOffset + (size.height - stageOffset) * 0.72)
    }

    private func pillowWidth(_ size: CGSize) -> CGFloat {
        min(size.width * 0.42, max(size.width * 0.3, director.jellyRect?.width ?? 0))
    }

    // MARK: Free

    /// How strong a coloured light may get: the candy sky is nearly white already.
    private var lift: Double { world == .candy ? 0.32 : 0.3 }

    /// A ring of light around the pillow, clear in the middle so Moodi stays crisp.
    private func halo(_ radius: CGFloat) -> RadialGradient {
        RadialGradient(gradient: Gradient(stops: [
            .init(color: world.glow.opacity(0), location: 0),
            .init(color: world.glow.opacity(0), location: 0.3),
            .init(color: world.glow.opacity(lift), location: 0.6),
            .init(color: world.glow.opacity(lift * 0.3), location: 0.82),
            .init(color: world.glow.opacity(0), location: 1),
        ]), center: .center, startRadius: 0, endRadius: radius)
    }

    private func freeGlow(_ size: CGSize) -> some View {
        let level = director.flowLevel
        let p = pillow(size), w = pillowWidth(size)
        return Ellipse()
            .fill(halo(w * 0.7))
            .frame(width: w * 1.4, height: w * 0.9)
            .scaleEffect(0.85 + 0.25 * level)
            .position(p)
            .opacity(min(1, level * 1.4))
    }

    // MARK: Rhythm

    private func beatPulse(_ size: CGSize, date: Date) -> some View {
        let u = director.rhythmPhase()
        // bright right on the beat, fading over a third of the beat; a faint swell just before it
        let after = pow(max(0, 1 - u / 0.33), 2)
        let before = pow(max(0, (u - 0.8) / 0.2), 2) * 0.35
        let streak = min(1, Double(director.combo) / 8)
        let hitAge = director.lastHit.map { date.timeIntervalSince($0.at) } ?? 9
        let good = (director.lastHit?.accuracy ?? 0) > 0
        let hit = good ? max(0, 1 - hitAge / 0.35) : 0
        let beat = (after + before) * (0.45 + 0.35 * streak) * (reduceMotion ? 0.5 : 1)
        return ZStack {
            edgeGlow(size, color: world.glow, strength: beat)
            edgeGlow(size, color: world.flashColor, strength: hit * 0.6)
        }
    }

    /// Light along all four edges of the screen, fading toward the middle.
    private func edgeGlow(_ size: CGSize, color: Color, strength: Double) -> some View {
        Rectangle()
            .fill(EllipticalGradient(colors: [.clear, color.opacity(0.4), color.opacity(0.9)],
                                     center: .center, startRadiusFraction: 0.6, endRadiusFraction: 1.08))
            .frame(width: size.width, height: size.height)
            .opacity(max(0, min(1, strength)) * (world == .candy ? 0.6 : 0.8))
    }

    // MARK: Breath

    private func breathTide(_ size: CGSize, date: Date) -> some View {
        let since = date.timeIntervalSince(director.breathStepAt)
        let held = director.heldSeconds()
        let swell: Double = {
            switch director.breathStep {
            case .inhale: return ease(min(1, held / 4))
            case .exhale: return ease(max(0, 1 - since / director.exhaleSeconds))
            case .ready: return 0.06 + 0.05 * sin(since * 1.2)
            }
        }()
        let p = pillow(size), w = pillowWidth(size)
        return ZStack {
            // a calm frame: the edges settle a little darker in breath mode
            Rectangle()
                .fill(EllipticalGradient(colors: [.clear, Palette.ink.opacity(0.34)],
                                         center: .center, startRadiusFraction: 0.45, endRadiusFraction: 1.1))
            // light rising from the pillow with the breath
            Ellipse()
                .fill(halo(w * 0.8))
                .frame(width: w * 1.6, height: w * 1.1)
                .scaleEffect(0.7 + 0.5 * swell)
                .position(x: p.x, y: p.y - CGFloat(swell) * size.height * 0.06)
                .opacity(0.2 + 0.8 * swell)
        }
    }

    private func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}
