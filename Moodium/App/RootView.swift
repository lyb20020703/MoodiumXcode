import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @State private var margins = ScreenMargins()
    @State private var hinge = RootView.initialHinge

    var body: some View {
        // Measure the device safe area here, then run every screen full screen with
        // ScreenMargins for its edge controls (see ScreenMargins).
        Color.clear
            .readSafeArea { safe in margins = Self.margins(for: safe) }
            .overlay {
                // the whole screen: where the Duo's fold crosses it, if it does
                GeometryReader { geo in
                    let found = Crease.detect(geo)
                    // half folded on the magnetic base the MagSafe half (the system's top) lies flat:
                    // turn over (also when the hinge can't be read, the app's usual setup)
                    let folded = hinge.partiallyOpen || hinge.angle == nil
                    let flip = found != nil && folded && BaseFlip.enabled
                    let crease = flip ? found?.mirrored(height: geo.size.height) : found
                    screens
                        .environment(\.crease, crease)
                        .environment(\.screenMargins, flip ? margins.turnedOver : margins)
                        .rotationEffect(.degrees(flip ? 180 : 0))
                        .onAppear { BaseFlip.active = flip }
                        .onChange(of: flip) { _, f in BaseFlip.active = f }
                    #if MOODIUM_AUTOPILOT
                    // CREASE_LINE=1 marks the fold in test screenshots
                    if let found, ProcessInfo.processInfo.environment["CREASE_LINE"] != nil {
                        Rectangle().fill(.red.opacity(0.35)).frame(height: found.band.height)
                            .position(x: found.band.midX, y: found.band.midY).allowsHitTesting(false)
                    }
                    #endif
                }
                .ignoresSafeArea()
            }
            .environment(\.screenMargins, margins)
            .environment(\.hinge, hinge)
            .modifier(HingeObserver { hinge = $0 })
    }

    private static var initialHinge: HingeState {
        #if MOODIUM_AUTOPILOT
        if let simulated = HingeSimulation.state { return simulated }
        #endif
        return HingeState()
    }

    private static func margins(for safe: EdgeInsets) -> ScreenMargins {
        #if MOODIUM_AUTOPILOT
        // SAFE=leading,top,bottom pretends to be a phone with that safe area (e.g. 62,0,21 = iPhone 17 Pro).
        if let v = ProcessInfo.processInfo.environment["SAFE"]?.split(separator: ",").compactMap({ Double($0) }), v.count == 3 {
            return .fit(EdgeInsets(top: v[1], leading: v[0], bottom: v[2], trailing: v[0]))
        }
        #endif
        return .fit(safe)
    }

    private var screens: some View {
        ZStack {
            Palette.ink.ignoresSafeArea()
            switch app.stage {
            case .opening:
                OpeningView().transition(.opacity)
            case .home:
                HomeView().transition(.opacity)
            case .select:
                WorldSelectView().transition(.opacity)
            case .squeeze(let world):
                SqueezeView(world: world).id(world).transition(.opacity)
            case .wish(let world):
                WishView(world: world).id("wish-\(world.rawValue)").transition(.opacity)
            }
            if let request = app.moodCheck {
                MoodCheckView(request: request).transition(.opacity).zIndex(5)
            }
            // Soft colour flash used when stepping into a world.
            if let flash = app.flash {
                flash.ignoresSafeArea().allowsHitTesting(false).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.55), value: app.stage)
        .animation(.easeInOut(duration: 0.45), value: app.flash)
        .animation(.easeInOut(duration: 0.35), value: app.moodCheck)
        #if MOODIUM_AUTOPILOT
        .overlay { if ProcessInfo.processInfo.environment["OUTLINE"] != nil { DeviceOutline() } }
        #endif
    }
}
