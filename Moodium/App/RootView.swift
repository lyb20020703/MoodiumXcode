import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ZStack {
            Palette.ink.ignoresSafeArea()
            switch app.stage {
            case .opening:
                OpeningView().transition(.opacity)
            case .select:
                WorldSelectView().transition(.opacity)
            case .squeeze(let world):
                SqueezeView(world: world).id(world).transition(.opacity)
            }
            // Soft colour flash used when stepping into a world.
            if let flash = app.flash {
                flash.ignoresSafeArea().allowsHitTesting(false).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.55), value: app.stage)
        .animation(.easeInOut(duration: 0.45), value: app.flash)
    }
}
