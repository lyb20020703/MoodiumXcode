import SwiftUI

/// Port of the visionOS GlassSlideToEnter: glass track with a world tint, a glossy candy-like
/// knob, a fill that follows the knob, and the label fading as you slide.
struct GlassSlideToEnter: View {
    let world: MoodWorld
    let label: String
    let busyLabel: String
    var onComplete: () -> Void

    @State private var drag: CGFloat = 0
    @State private var completed = false
    @State private var passedThreshold = false

    private let width: CGFloat = 350
    private let height: CGFloat = 64
    private let knob: CGFloat = 54
    private let inset: CGFloat = 5

    var body: some View {
        let travel = width - knob - inset * 2
        let p = completed ? 1 : min(max(drag / travel, 0), 1)

        ZStack(alignment: .leading) {
            // Track: blur, world tint, and the white sheen from slider_track_tint.svg
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(world.tint.opacity(0.32))
            Capsule().fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.06), .white.opacity(0.14)],
                                          startPoint: .top, endPoint: .bottom))
            // Fill behind the knob
            Capsule()
                .fill(LinearGradient(colors: [world.fill.opacity(0.75), world.fill], startPoint: .leading, endPoint: .trailing))
                .frame(width: knob + inset * 2 + p * travel)
                .opacity(completed ? 1 : min(1, Double(p) * 3))
            // Glow rim
            Capsule().stroke(world.glow, lineWidth: 3).blur(radius: 6).opacity(0.15 + 0.6 * Double(p))
            Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.2), .white.opacity(0.6)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)

            Text(completed ? busyLabel : label)
                .font(.moodium(17, .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.leading, knob + inset * 2 + 34)
                .padding(.trailing, 16)
                .opacity(completed ? 1 : max(0, 1 - Double(p) * 1.6))

            ChevronShimmer()
                .padding(.leading, knob + inset * 2 + 6)
                .opacity(completed ? 0 : max(0, 0.75 - Double(p) * 8))

            SliderKnob(world: world, completed: completed)
                .frame(width: knob, height: knob)
                .offset(x: inset + p * travel)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !completed else { return }
                            drag = max(0, value.translation.width)
                            let past = drag / travel > 0.82
                            if past != passedThreshold {
                                passedThreshold = past
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                        .onEnded { _ in
                            guard !completed else { return }
                            if drag / travel > 0.82 {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { completed = true }
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                onComplete()
                            } else {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.68)) { drag = 0 }
                                passedThreshold = false
                            }
                        }
                )
        }
        .frame(width: width, height: height)
        .shadow(color: world.glow.opacity(0.25 + 0.3 * Double(p)), radius: 18, y: 6)
        .animation(.easeOut(duration: 0.2), value: completed)
    }
}

/// The glossy knob from slider_knob_candy.svg / slider_knob_nature.svg.
private struct SliderKnob: View {
    let world: MoodWorld
    let completed: Bool

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            ZStack {
                Circle().fill(RadialGradient(colors: world.knobStops, center: UnitPoint(x: 0.34, y: 0.28),
                                             startRadius: 0, endRadius: s * 0.8))
                Circle().fill(RadialGradient(colors: [.white.opacity(0.28), .clear], center: UnitPoint(x: 0.5, y: 0.9),
                                             startRadius: 0, endRadius: s * 0.6))
                Ellipse().fill(.white.opacity(0.55))
                    .frame(width: s * 0.46, height: s * 0.26)
                    .rotationEffect(.degrees(-24))
                    .offset(x: -s * 0.11, y: -s * 0.22)
                Circle().strokeBorder(LinearGradient(colors: [.white, .white.opacity(0.25), .white.opacity(0.7)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
                Image(systemName: completed ? "checkmark" : "chevron.right")
                    .font(.system(size: s * 0.34, weight: .bold))
                    .foregroundStyle(world.fill.opacity(0.95))
                    .shadow(color: .white.opacity(0.6), radius: 1)
                    .contentTransition(.symbolEffect(.replace))
            }
            .shadow(color: world.glow.opacity(0.55), radius: 8)
        }
    }
}

/// Three chevrons with a travelling highlight, hinting the slide direction.
private struct ChevronShimmer: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: -3) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t * 1.4 - Double(i) * 0.22).truncatingRemainder(dividingBy: 1.4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .opacity(0.25 + 0.75 * max(0, sin(phase / 1.4 * .pi)))
                }
            }
            .foregroundStyle(.white)
        }
    }
}
