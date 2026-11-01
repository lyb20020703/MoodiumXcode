import SwiftUI

/// The 2D Moodi for the home screen, built from the visionOS expression art (moodi_*):
/// - the face follows today's mood;
/// - it floats, breathes (squash and stretch) and sways a little, with a soft shadow below
///   that shrinks as it rises;
/// - it blinks every few seconds (the closed-eye "calm" art for a moment);
/// - a glow in the mood colour and a few twinkles drift around it;
/// - tap: it squishes, hops, smiles and puffs out little stars.
struct FlatMoodi: View {
    var mood: MoodKind?
    var size: CGFloat
    var onPoke: () -> Void = {}

    @State private var pokeAt: Date?
    @State private var bornAt = Date()

    private var face: String { mood?.moodiFace ?? "moodi_happy" }
    private var tint: Color { mood?.tint ?? Palette.lavender }

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date
            let t = now.timeIntervalSinceReferenceDate
            let born = now.timeIntervalSince(bornAt)
            let poke = pokeAt.map { now.timeIntervalSince($0) } ?? 99

            // entrance: drop in with a springy settle
            let enter = born < 0.9 ? 1 - exp(-6 * born) * cos(9 * born) : 1
            // idle float, breathing and sway
            let bob = sin(t * 1.8) * size * 0.04
            let breathe = 0.03 * sin(t * 1.8 + 0.7)
            let sway = 3.5 * sin(t * 0.9)
            // poke: damped squish and a little hop
            let squish = poke < 1.2 ? 0.24 * exp(-5.5 * poke) * cos(16 * poke) : 0
            let hop = poke < 0.5 ? sin(.pi * poke / 0.5) * size * 0.14 : 0
            let sx = (1 + breathe + squish) * enter
            let sy = (1 - breathe - squish) * enter
            let lift = bob + hop

            ZStack {
                // glow in the mood colour
                Image(asset: "glow_radial").resizable()
                    .frame(width: size * 2.0, height: size * 2.0)
                    .colorMultiply(tint)
                    .opacity(0.55 + 0.1 * sin(t * 1.2))
                Image(asset: "mood_token_halo").resizable()
                    .frame(width: size * 1.45, height: size * 1.45)
                    .colorMultiply(tint)
                    .opacity(0.18)
                    .blur(radius: 2)
                    .rotationEffect(.degrees(t * 10))

                twinkles(t: t)

                // ground shadow, smaller and lighter as Moodi rises
                Ellipse()
                    .fill(RadialGradient(colors: [.black.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: size * 0.36))
                    .frame(width: size * (0.72 - lift / size * 0.6), height: size * 0.16)
                    .opacity(0.8 - Double(lift / size) * 1.2)
                    .offset(y: size * 0.56)

                Image(asset: faceName(now: now, poke: poke))
                    .resizable().scaledToFit()
                    .frame(width: size)
                    .scaleEffect(x: sx, y: sy, anchor: .bottom)
                    .rotationEffect(.degrees(sway))
                    .offset(y: -lift)
                    .shadow(color: tint.opacity(0.45), radius: 16)

                if poke < 1.0 { puff(poke) }
            }
            .frame(width: size * 1.6, height: size * 1.4)
            .contentShape(Circle().scale(0.7))
            .onTapGesture {
                pokeAt = Date()
                onPoke()
            }
        }
    }

    /// Blinks: the closed-eye art for 0.13 s every ~4 s (sometimes twice); a smile right after a poke.
    private func faceName(now: Date, poke: TimeInterval) -> String {
        if poke < 1.3 { return "moodi_happy" }
        if mood == .calm || mood == .low { return face }   // eyes already soft / closed
        let t = now.timeIntervalSinceReferenceDate
        let cycle = t.truncatingRemainder(dividingBy: 4.3)
        let second = Int(t / 4.3) % 3 == 0 && cycle > 0.3 && cycle < 0.43
        return cycle < 0.13 || second ? "moodi_calm" : face
    }

    /// A few twinkles drifting on slow orbits.
    private func twinkles(t: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                let a = t * (0.25 + 0.05 * Double(i)) + Double(i) * 1.26
                let r = size * (0.66 + 0.08 * Double(i % 2))
                let tw = 0.5 + 0.5 * sin(t * (1.4 + 0.3 * Double(i)) + Double(i))
                Image(asset: i % 2 == 0 ? "fx_twinkle" : "fx_sparkle").resizable()
                    .frame(width: size * (0.07 + 0.05 * tw), height: size * (0.07 + 0.05 * tw))
                    .colorMultiply(i % 2 == 0 ? .white : tint)
                    .opacity(0.25 + 0.6 * tw)
                    .offset(x: cos(a) * r, y: sin(a) * r * 0.6 - size * 0.05)
            }
        }
    }

    /// Little stars puffing out after a poke.
    private func puff(_ p: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                let angle = -Double.pi / 2 + (Double(i) - 3) * 0.42
                let d = size * (0.35 + 0.55 * min(1, p / 0.6))
                Image(asset: "fx_star").resizable()
                    .frame(width: size * 0.1, height: size * 0.1)
                    .colorMultiply(i % 2 == 0 ? tint : .white)
                    .rotationEffect(.degrees(p * 220 + Double(i) * 40))
                    .offset(x: cos(angle) * d, y: sin(angle) * d * 0.8 - size * 0.1)
                    .opacity(1 - p)
            }
        }
        .allowsHitTesting(false)
    }
}
