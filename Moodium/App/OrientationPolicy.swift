import SwiftUI
import UIKit

/// Which way the app may turn.
///
/// On an ordinary iPhone (and the iPhone Duo's outer display) Moodium is landscape only: the phone
/// lies on the sensory bag sideways. The Duo's inner display is nearly square, and when it is half
/// folded with the fold running across ("tabletop") it is in portrait. A landscape-only app is
/// shrunk into a small letterboxed window there, so the Info.plist lists portrait too and the
/// landscape lock is applied here at runtime, only on phone-shaped screens.
enum OrientationPolicy {
    /// Long side ÷ short side below this is a near-square screen (Duo inner ≈ 1.42, iPhones ≈ 2.1+).
    private static let squareish = 1.7

    static func mask(for window: UIWindow?) -> UIInterfaceOrientationMask {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return .landscape }
        guard let screen = window?.windowScene?.screen ?? activeScene?.screen else { return .landscape }
        let b = screen.bounds
        let long = max(b.width, b.height), short = min(b.width, b.height)
        guard short > 0 else { return .landscape }
        return long / short < squareish ? .allButUpsideDown : .landscape
    }

    private static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ??
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    /// Ask UIKit to read the mask again, e.g. after the Duo was opened or closed (the app moved
    /// to the other display).
    @MainActor static func refresh() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }
}

final class MoodiumAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationPolicy.mask(for: window)
    }
}

/// Re-checks the orientation policy whenever the window changes size (opening or closing the Duo).
struct OrientationPolicyRefresher: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { OrientationPolicy.refresh() }
                    .onChange(of: geo.size) { _, _ in OrientationPolicy.refresh() }
            }
        )
    }
}
