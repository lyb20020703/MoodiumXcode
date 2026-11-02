import SwiftUI

// iPhone Duo support.
//
// When the Duo's inner display is half folded with the hinge running across the screen
// ("tabletop", like a small laptop), the squeeze world splits in two: the pillow, Moodi and
// every control sit on the bottom half, and the top half becomes a sky where the sparks of
// each squeeze fly up across the fold and burst like fireworks.
//
// The hinge APIs only exist in the iOS 27.1 SDK (Xcode 27.1). They are compiled only when the
// MOODIUM_DUO flag is set, which the project turns on automatically for iOS 27.1+ SDKs, so the
// app still builds with older Xcode versions; everywhere else the app looks as before.

/// What the hinge reports (live; used for effects, never for layout).
struct HingeState: Equatable {
    /// The device is part-way open (not closed, not flat).
    var partiallyOpen = false
    /// Hinge angle in degrees, when the device has a hinge.
    var angle: Double?
}

private struct HingeStateKey: EnvironmentKey { static let defaultValue = HingeState() }

extension EnvironmentValues {
    var hinge: HingeState {
        get { self[HingeStateKey.self] }
        set { self[HingeStateKey.self] = newValue }
    }
}

/// The two halves of the screen in tabletop posture, in the measuring view's coordinates.
struct TabletopFold: Equatable {
    /// The fold band itself (keep touch targets out of it).
    var band: CGRect
    /// Above the fold: the sky.
    var top: CGRect
    /// Below the fold: the stage and the controls.
    var bottom: CGRect
    /// 0…1, how far the fireworks may climb (more open → higher).
    var reach: Double

    /// Tabletop posture: the device is half open and the fold runs across the screen.
    static func detect(_ geo: GeometryProxy, hinge: HingeState) -> TabletopFold? {
        guard hinge.partiallyOpen, let band = divisionFrame(geo) else { return nil }
        let size = geo.size
        // A horizontal band that really splits the screen into a top and a bottom half.
        guard band.width > band.height, band.minY > size.height * 0.25, band.maxY < size.height * 0.75 else { return nil }
        let top = CGRect(x: 0, y: 0, width: size.width, height: band.minY)
        let bottom = CGRect(x: 0, y: band.maxY, width: size.width, height: size.height - band.maxY)
        // ~60° barely open → low bursts; ~120° and up → bursts near the top edge.
        let reach = hinge.angle.map { min(1, max(0, ($0 - 60) / 60)) } ?? 0.7
        return TabletopFold(band: band, top: top, bottom: bottom, reach: reach)
    }

    /// The fold ("division" reserved region) in this geometry's coordinates, while it is active.
    private static func divisionFrame(_ geo: GeometryProxy) -> CGRect? {
        #if MOODIUM_AUTOPILOT
        if let simulated = HingeSimulation.band(in: geo.size) { return simulated }
        #endif
        #if MOODIUM_DUO
        if #available(iOS 27.1, *) {
            return geo.reservedRegions(kind: .division).first?.frame
        }
        #endif
        return nil
    }
}

/// Feeds hinge changes into `onChange` on devices with a hinge (iPhone Duo).
struct HingeObserver: ViewModifier {
    let onChange: (HingeState) -> Void

    func body(content: Content) -> some View {
        #if MOODIUM_DUO
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                if let hinge = context.hinge {
                    onChange(HingeState(partiallyOpen: hinge.status == .partiallyOpen, angle: hinge.angle.degrees))
                } else {
                    onChange(HingeState())
                }
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if MOODIUM_AUTOPILOT
/// Test aid for the Mac build: FOLD=1 pretends to be a half-folded iPhone Duo (use a
/// 669x951 window), FOLD_ANGLE sets the hinge angle (default 90).
enum HingeSimulation {
    static var state: HingeState? {
        let env = ProcessInfo.processInfo.environment
        guard env["FOLD"] != nil else { return nil }
        return HingeState(partiallyOpen: true, angle: env["FOLD_ANGLE"].flatMap(Double.init) ?? 90)
    }

    static func band(in size: CGSize) -> CGRect? {
        guard state != nil else { return nil }
        return CGRect(x: 0, y: size.height / 2 - 14, width: size.width, height: 28)
    }
}
#endif
