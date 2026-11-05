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

/// Where the fold crosses the screen: the iPhone Duo's inner display held upright, flat or half
/// folded. The fold always runs across the middle there, so screens keep their pieces off it:
/// things to look at above, things to touch below (the half you hold or rest on the table).
struct Crease: Equatable {
    /// The fold band itself.
    var band: CGRect
    /// Above the fold.
    var top: CGRect
    /// Below the fold.
    var bottom: CGRect

    /// Room to leave between content and the band.
    static let gap: CGFloat = 12

    /// `geo` must cover the whole screen.
    static func detect(_ geo: GeometryProxy) -> Crease? {
        let size = geo.size
        guard size.width > 0, size.height > size.width else { return nil }
        var band: CGRect?
        #if MOODIUM_DUO
        if #available(iOS 27.1, *) {
            band = geo.reservedRegions(kind: .division).first?.frame
        }
        #endif
        #if MOODIUM_AUTOPILOT
        // the Mac test build: a portrait window stands for the Duo held upright
        let foldable = true
        #else
        // fallback while the system reports no region (e.g. lying flat): a near-square phone screen
        let foldable = UIDevice.current.userInterfaceIdiom == .phone && size.height / size.width < 1.7
        #endif
        if band == nil, foldable {
            band = CGRect(x: 0, y: size.height / 2 - 14, width: size.width, height: 28)
        }
        // only a horizontal band that really splits the screen into a top and a bottom half
        guard let band, band.width > band.height,
              band.minY > size.height * 0.25, band.maxY < size.height * 0.75 else { return nil }
        return Crease(band: band,
                      top: CGRect(x: 0, y: 0, width: size.width, height: band.minY),
                      bottom: CGRect(x: 0, y: band.maxY, width: size.width, height: size.height - band.maxY))
    }
}

extension Crease {
    /// The same fold seen in a view turned upside down (see `BaseFlip`).
    func mirrored(height h: CGFloat) -> Crease {
        func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height) }
        return Crease(band: flip(band), top: flip(bottom), bottom: flip(top))
    }
}

/// The iPhone Duo's MagSafe is in the half that is on top when the inner display is held
/// upright the system's way. On our magnetic base that half lies flat underneath, so the
/// phone is upside down for the system. While the phone is half folded (or the hinge can't be
/// read) and the fold crosses the screen, the app turns its whole interface over itself: "down" is always the MagSafe half on the base, the upright
/// half shows the sky and the energy ring. (The system's own upside-down rotation stays off,
/// see `OrientationPolicy`, so the two never add up.)
enum BaseFlip {
    /// The interface is turned over right now (set and read on the main thread; the motion
    /// code reads it to flip its axes).
    nonisolated(unsafe) static var active = false

    /// The orientation the user sees: the system's one, turned over while flipped.
    static func visible(_ o: UIInterfaceOrientation) -> UIInterfaceOrientation {
        guard active else { return o }
        switch o {
        case .portrait: return .portraitUpsideDown
        case .portraitUpsideDown: return .portrait
        default: return o
        }
    }

    static var enabled: Bool {
        #if MOODIUM_AUTOPILOT
        // the Mac test build shows the layout the right way up unless MAGSAFE_FLIP is set
        return ProcessInfo.processInfo.environment["MAGSAFE_FLIP"] != nil
        #else
        return true
        #endif
    }
}

private struct CreaseKey: EnvironmentKey { static let defaultValue: Crease? = nil }

extension EnvironmentValues {
    /// The fold across the screen, when there is one (see `Crease`).
    var crease: Crease? {
        get { self[CreaseKey.self] }
        set { self[CreaseKey.self] = newValue }
    }
}

/// Two pieces kept off the fold: `top` fills the half above it, `bottom` the half below
/// (each centred unless aligned otherwise). Place it so it covers the whole screen.
struct CreaseStack<Top: View, Bottom: View>: View {
    let crease: Crease
    var topAlignment: Alignment = .center
    var bottomAlignment: Alignment = .center
    @ViewBuilder var top: Top
    @ViewBuilder var bottom: Bottom

    var body: some View {
        VStack(spacing: 0) {
            top
                .padding(.bottom, Crease.gap)
                .frame(maxWidth: .infinity)
                .frame(height: crease.top.height, alignment: topAlignment)
            Color.clear.frame(height: crease.band.height)
            bottom
                .padding(.top, Crease.gap)
                .frame(maxWidth: .infinity)
                .frame(height: crease.bottom.height, alignment: bottomAlignment)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

enum CreaseHalf { case top, bottom }

/// Moves a centred card (settings, help, journal…) wholly into one half of the screen when the
/// fold crosses it, shrinking it if it would not fit. The card's container must cover the screen.
private struct OffCrease: ViewModifier {
    @Environment(\.crease) private var crease
    @Environment(\.screenMargins) private var m
    let half: CreaseHalf
    @State private var natural = CGSize.zero

    func body(content: Content) -> some View {
        if let crease {
            let r = half == .top ? crease.top : crease.bottom
            let edge = half == .top ? m.top : m.bottom
            let room = r.height - Crease.gap * 2 - edge
            let scale = natural.height > 0 ? min(1, room / natural.height) : 1
            let target = half == .top ? r.midY + edge / 2 : r.midY - edge / 2
            content
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { natural = g.size }
                        .onChange(of: g.size) { _, size in natural = size }
                })
                .scaleEffect(scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: target - crease.bottom.maxY / 2)
        } else {
            content
        }
    }
}

extension View {
    /// Keep this centred card off the fold (see `OffCrease`); controls go below it by default.
    func offCrease(_ half: CreaseHalf = .bottom) -> some View { modifier(OffCrease(half: half)) }
}

/// The squeeze world split at the fold: a sky above, the stage and controls below.
struct TabletopFold: Equatable {
    /// The fold band itself (keep touch targets out of it).
    var band: CGRect
    /// Above the fold: the sky.
    var top: CGRect
    /// Below the fold: the stage and the controls.
    var bottom: CGRect
    /// 0…1, how far the fireworks may climb (more open → higher).
    var reach: Double

    /// Where the 3D stage draws: the bottom half plus the fold band, so its own sky fills the
    /// band and no dark gap shows (the controls still stay in `bottom`).
    var stage: CGRect { CGRect(x: bottom.minX, y: band.minY, width: bottom.width, height: bottom.maxY - band.minY) }

    /// Whenever the fold crosses the screen, flat or half open.
    static func detect(crease: Crease?, hinge: HingeState) -> TabletopFold? {
        guard let crease else { return nil }
        // ~60° barely open → low bursts; ~120° and up (or flat) → bursts near the top edge.
        let reach = hinge.partiallyOpen ? hinge.angle.map { min(1, max(0, ($0 - 60) / 60)) } ?? 0.7 : 0.85
        return TabletopFold(band: crease.band, top: crease.top, bottom: crease.bottom, reach: reach)
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
/// Test aid for the Mac build: FOLD=1 pretends the iPhone Duo is half folded, FOLD_ANGLE sets the
/// hinge angle (default 90). Any portrait window (use 669x951) already has the fold across it.
enum HingeSimulation {
    static var state: HingeState? {
        let env = ProcessInfo.processInfo.environment
        guard env["FOLD"] != nil else { return nil }
        return HingeState(partiallyOpen: true, angle: env["FOLD_ANGLE"].flatMap(Double.init) ?? 90)
    }
}
#endif
