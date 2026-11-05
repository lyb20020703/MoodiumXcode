import SwiftUI

/// What the sensory-bag guide shows live, fed by the director while the guide is open.
final class BagProbe: ObservableObject {
    /// -1…1, how far the phone is tipped from rest; + when the screen's right side goes down.
    @Published var tilt = 0.0
    /// 0…1, the try-it meter.
    @Published var progress = 0.0
    /// Last time the phone rocked, so the drawing follows the real phone only while it moves.
    @Published var lastMove = Date.distantPast
}

/// First visit to a world: how to use the sensory bag, with a live try-it.
/// A side view of the bag with the phone lying on top. Once you press the bag, the phone in the
/// drawing follows the real phone's tilt (exaggerated, like a spirit level), the hand on the
/// pressed side lights up, and a meter fills as you rock it.
struct BagGuide: View {
    @EnvironmentObject private var app: AppModel
    let world: MoodWorld
    @ObservedObject var probe: BagProbe
    let onDone: () -> Void

    private var done: Bool { probe.progress >= 1 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 22) {
                    illustration.frame(width: 230, height: 190)
                    steps.frame(width: 330, alignment: .leading)
                }
                VStack(spacing: 14) {
                    illustration.frame(width: 230, height: 170)
                    steps.frame(maxWidth: 330, alignment: .leading)
                }
            }
            .padding(Panel.padding)
            .glass(Panel.shape, tint: Palette.smoke, amount: 0.6)
            .padding(16)
            .offCrease()
        }
        .foregroundStyle(.white)
    }

    // MARK: Text side

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(app.t("感官袋用法", "Using the sensory bag")).font(.moodium(21, .bold))
            step(1, app.t("把感官袋平放在桌上，手机屏幕朝上放在正中间",
                          "Lay the bag flat on a table, phone in the middle, screen up"))
            step(2, app.t("轻按袋子左侧或右侧，手机会随之轻微摆动",
                          "Gently press the left or right side; the phone rocks slightly"))
            meter
            HStack(spacing: 12) {
                Button(app.t("开始", "Start")) { onDone() }
                    .buttonStyle(GlassButtonStyle(tint: world.accent, prominent: true, compact: true))
                    .scaleEffect(done ? 1.06 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: done)
                Text(app.t("没有感官袋时，也可以按压屏幕", "No bag? Press the screen instead"))
                    .font(.moodium(12))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.moodium(13, .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(world.accent.opacity(0.85)))
            Text(text)
                .font(.moodium(14))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var meter: some View {
        let green = Color(hex: 0x9BE8B4)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(done ? app.t("就是这样", "That's it")
                          : app.t("按几下，填满进度条", "Press a few times to fill the bar"))
                    .font(.moodium(14, .semibold))
                    .foregroundStyle(done ? green : .white)
                if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(green) }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule()
                        .fill(LinearGradient(colors: [world.accent.opacity(0.7), done ? green : world.accent],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, g.size.width * probe.progress))
                }
            }
            .frame(height: 10)
            .animation(.easeOut(duration: 0.2), value: probe.progress)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.t("试一试", "Try it"))
        .accessibilityValue("\(Int(probe.progress * 100))%")
    }

    // MARK: Drawing

    private var illustration: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let live = context.date.timeIntervalSince(probe.lastMove) < 1.5
            let tilt = live ? probe.tilt : demoTilt(t)
            drawing(tilt: tilt, live: live)
        }
        .accessibilityHidden(true)
    }

    /// Until the phone moves: press left, let go, press right, let go.
    private func demoTilt(_ t: Double) -> Double {
        let c = t.truncatingRemainder(dividingBy: 3.2) / 3.2
        func press(_ at: Double) -> Double {
            let u = (c - at) / 0.3
            return u > 0 && u < 1 ? sin(.pi * u) : 0
        }
        return -press(0.08) + press(0.58)
    }

    private func drawing(tilt: Double, live: Bool) -> some View {
        let angle = max(-1, min(1, tilt)) * 9      // exaggerated so a tenth of a degree shows
        let bagY: CGFloat = 40
        return ZStack {
            // table
            Capsule().fill(.white.opacity(0.18)).frame(width: 220, height: 3).offset(y: bagY + 33)
            // the bag: soft and squishy, leans a little with the press
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(LinearGradient(colors: [world.accent.opacity(0.95), world.accent.opacity(0.5)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) {
                    Capsule().fill(.white.opacity(0.35)).frame(width: 120, height: 6).offset(y: 7).blur(radius: 1.5)
                }
                .frame(width: 196, height: 62)
                .rotationEffect(.degrees(angle * 0.35))
                .offset(y: bagY)
            // the phone on top, rocking about the middle of the bag
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(hex: 0x2A2533))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.85), lineWidth: Panel.hairline))
                .overlay(alignment: .top) { Capsule().fill(world.accent).frame(width: 96, height: 2).offset(y: 1.5) }
                .frame(width: 128, height: 11)
                .offset(y: -36)
                .rotationEffect(.degrees(angle))
                .offset(y: bagY)
                .shadow(color: world.accent.opacity(live ? 0.6 : 0), radius: 8)
            // hands pressing the bag's sides
            ForEach([-1.0, 1.0], id: \.self) { side in
                let press = max(0, tilt * side)
                Image(systemName: "hand.point.down.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.3 + 0.7 * press))
                    .offset(x: side * 80, y: -32 + 16 * press)
            }
            Text(live ? app.t("正在跟随你的手机", "Following your phone")
                      : app.t("左右各按一下", "Press left, then right"))
                .font(.moodium(12, .semibold))
                .foregroundStyle(live ? world.accent : Palette.textMuted)
                .offset(y: bagY + 50)
        }
    }
}
