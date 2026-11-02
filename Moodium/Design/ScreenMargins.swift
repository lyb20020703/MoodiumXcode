import SwiftUI

/// Edge margins for on-screen controls, worked out from the device's safe area.
///
/// The app runs full screen (every screen ignores the safe area) and places its corner
/// buttons and side panels with these margins instead. In landscape, iOS reports the full
/// Dynamic Island / notch width on both sides (about 62 pt on an iPhone 17 Pro), which leaves
/// far too much empty space next to the rounded corners; these margins sit just inside the
/// island and the corner curve, so every model gets an even frame.
struct ScreenMargins: Equatable {
    var top: CGFloat = 12
    var leading: CGFloat = 20
    var bottom: CGFloat = 12
    var trailing: CGFloat = 20

    var insets: EdgeInsets { EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing) }

    static func fit(_ safe: EdgeInsets) -> ScreenMargins {
        let side = max(safe.leading, safe.trailing)
        // Home-button phones (iPhone SE): square corners, nothing to dodge.
        guard side > 0 || safe.bottom > 0 || safe.top > 24 else { return ScreenMargins() }
        if side > 0 {
            // Landscape with a notch or Dynamic Island: clear the island (it ends about 48 pt in),
            // keep the same gap on both sides, and stay off the home indicator.
            let h = max(side - 12, 32)
            return ScreenMargins(top: max(safe.top, 16), leading: h, bottom: max(safe.bottom - 4, 14), trailing: h)
        }
        // Portrait or iPad: follow the reported insets with a small extra gap.
        return ScreenMargins(top: safe.top + 8, leading: 20, bottom: max(safe.bottom, 14), trailing: 20)
    }
}

private struct ScreenMarginsKey: EnvironmentKey {
    static let defaultValue = ScreenMargins()
}

extension EnvironmentValues {
    var screenMargins: ScreenMargins {
        get { self[ScreenMarginsKey.self] }
        set { self[ScreenMarginsKey.self] = newValue }
    }
}

private struct SafeAreaKey: PreferenceKey {
    static let defaultValue = EdgeInsets()
    static func reduce(value: inout EdgeInsets, nextValue: () -> EdgeInsets) { value = nextValue() }
}

extension View {
    /// Reports the device safe area of this view's frame (place it on a view that respects the safe area).
    func readSafeArea(_ onChange: @escaping (EdgeInsets) -> Void) -> some View {
        background(GeometryReader { g in Color.clear.preference(key: SafeAreaKey.self, value: g.safeAreaInsets) })
            .onPreferenceChange(SafeAreaKey.self, perform: onChange)
    }
}

#if MOODIUM_AUTOPILOT
/// Test aid: draws an iPhone 17 Pro landscape outline (rounded corners and the Dynamic Island)
/// over the Mac test window, so screenshots show how the edges line up on the real phone.
struct DeviceOutline: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(.black)
                    .mask {
                        Rectangle().overlay {
                            RoundedRectangle(cornerRadius: 62, style: .continuous).blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
                Capsule().fill(.black)
                    .frame(width: 37, height: 126)
                    .position(x: 11 + 18.5, y: geo.size.height / 2)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
#endif
