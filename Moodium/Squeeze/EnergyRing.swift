import SwiftUI

/// The visionOS energy ring (ui-refresh.tokens.json → energyRing), floating above the pillow:
/// 40 dots that light up with energy, a breathing head dot, four gift gems at 20/50/80/100 %
/// that pop with a ripple, one big number, and dimming when full or idle.
struct EnergyRing: View {
    var energy: Double
    var accent: Color
    var lastSqueeze: Date

    @State private var popDot: (index: Int, at: TimeInterval) = (-1, 0)
    @State private var gemReached: [Int: TimeInterval] = [:]
    @State private var fullAt: TimeInterval?

    private let count = 40
    private let radius: CGFloat = 54
    private let gemRadius: CGFloat = 67
    private let gemDots = [7, 19, 31, 39]
    private let gemPercents = [0.2, 0.5, 0.8, 1.0]

    var body: some View {
        TimelineView(.animation) { context in
            ring(at: context.date.timeIntervalSinceReferenceDate)
        }
        .onChange(of: energy) { old, new in
            let now = Date().timeIntervalSinceReferenceDate
            let oldLit = Int(floor(old * Double(count) + 1e-6)), newLit = Int(floor(new * Double(count) + 1e-6))
            if newLit > oldLit { popDot = (newLit - 1, now) }
            for (g, pct) in gemPercents.enumerated() where old < pct - 1e-6 && new >= pct - 1e-6 {
                gemReached[g] = now
            }
            if new >= 1, old < 1 { fullAt = now }
            if new == 0 { gemReached = [:]; fullAt = nil; popDot = (-1, 0) }
        }
        .allowsHitTesting(false)
    }

    private func ring(at t: TimeInterval) -> some View {
        let lit = Int(floor(energy * Double(count) + 1e-6))
        let head = energy > 0 && energy < 1 ? lit - 1 : -1
        return ZStack {
            Image(asset: "energy_halo").resizable().frame(width: 200, height: 200)
            ForEach(0..<count, id: \.self) { i in
                dot(i, lit: lit, head: head, t: t)
            }
            ForEach(0..<gemDots.count, id: \.self) { g in
                gem(g, t: t)
            }
            number
        }
        .frame(width: 180, height: 180)
        .opacity(dimming(t))
    }

    private func dot(_ i: Int, lit: Int, head: Int, t: TimeInterval) -> some View {
        let p = point(forDot: i, radius: radius)
        let isHead = i == head
        let pop: Double = popDot.index == i ? max(0, 1 - (t - popDot.at) / 0.35) : 0
        let breathe: Double = isHead ? 1 + 0.075 * (1 - cos(2 * .pi * t / 1.6)) : 1
        let scale: Double = breathe * (1 + 0.8 * pop) * (1 + 0.6 * fullWave(i, t))
        let side: CGFloat = isHead ? 36 : 24
        let color: Color = isHead ? blend(accent, .white, 0.45) : accent
        return Group {
            if i < lit {
                Image(asset: isHead ? "energy_dot_head" : "energy_dot_on")
                    .renderingMode(.template)
                    .resizable()
                    .foregroundStyle(color)
                    .frame(width: side, height: side)
                    .scaleEffect(scale)
            } else {
                Image(asset: "energy_dot_off").resizable().frame(width: 12, height: 12)
            }
        }
        .offset(x: p.x, y: p.y)
    }

    private func gem(_ g: Int, t: TimeInterval) -> some View {
        let p = point(forDot: gemDots[g], radius: gemRadius)
        let reached = energy >= gemPercents[g] - 1e-6
        let since: TimeInterval = gemReached[g].map { t - $0 } ?? 10
        let popScale: Double = since < 0.5 ? 1 + 0.5 * sin(.pi * since / 0.5) : 1
        return ZStack {
            ripple(since, delay: 0)
            ripple(since, delay: 0.12)
            if reached {
                Image(asset: "energy_gem_full").renderingMode(.template).resizable()
                    .foregroundStyle(accent).frame(width: 36, height: 36)
            } else {
                Image(asset: "energy_gem_empty").resizable().frame(width: 22, height: 22)
            }
        }
        .scaleEffect(popScale)
        .offset(x: p.x, y: p.y)
    }

    private var number: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1) {
            Text("\(Int((energy * 100).rounded()))")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: energy))
            Text("%").font(.system(size: 14, weight: .bold, design: .rounded)).opacity(0.72)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 4)
    }

    /// angleOfDot = 90 − (i + 1) · 9°, clockwise from 12 o'clock; dot 39 sits at the top.
    private func point(forDot i: Int, radius r: CGFloat) -> CGPoint {
        let a = (90 - Double(i + 1) * 9) * .pi / 180
        return CGPoint(x: r * CGFloat(cos(a)), y: -r * CGFloat(sin(a)))
    }

    private func ripple(_ since: TimeInterval, delay: TimeInterval) -> some View {
        let k = (since - delay) / 0.7
        let visible = k >= 0 && k <= 1
        return Image(asset: "energy_ripple").renderingMode(.template).resizable()
            .foregroundStyle(accent)
            .frame(width: 64, height: 64)
            .scaleEffect(visible ? 0.5 + 1.1 * k : 0.5)
            .opacity(visible ? 0.8 * (1 - k) : 0)
    }

    /// A bright wave runs once around the ring when it fills.
    private func fullWave(_ i: Int, _ t: TimeInterval) -> Double {
        guard let fullAt, t - fullAt < 0.8 else { return 0 }
        let front = (t - fullAt) / 0.8
        let d = Double(i) / Double(count) - front
        return exp(-(d * d) / 0.004)
    }

    /// Full: fade to 40 % after 3 s. Idle 8 s: fade to 60 %; a squeeze wakes it.
    private func dimming(_ t: TimeInterval) -> Double {
        if let fullAt {
            let k = min(1, max(0, (t - fullAt - 3) / 0.6))
            return 1 - 0.6 * k
        }
        let idle = Date().timeIntervalSince(lastSqueeze)
        let k = min(1, max(0, (idle - 8) / 0.6))
        return 1 - 0.4 * k
    }

    private func blend(_ a: Color, _ b: Color, _ f: Double) -> Color {
        let ua = UIColor(a), ub = UIColor(b)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        ua.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        ub.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let k = CGFloat(f)
        return Color(red: Double(r1 + (r2 - r1) * k), green: Double(g1 + (g2 - g1) * k), blue: Double(b1 + (b2 - b1) * k))
    }
}
