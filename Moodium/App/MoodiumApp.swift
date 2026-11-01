import SwiftUI
import AVFoundation

@main
struct MoodiumApp: App {
    @StateObject private var app = AppModel()

    init() {
        // Moodi's voice is part of the story, so play even when the ring/silent switch is on.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}
