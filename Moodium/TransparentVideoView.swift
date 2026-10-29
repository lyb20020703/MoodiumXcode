import SwiftUI
import AVFoundation

/// Composites the video's encoded alpha directly over the SwiftUI background.
struct TransparentVideoView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> TransparentPlayerSurface {
        let view = TransparentPlayerSurface()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.playerLayer.isOpaque = false
        view.playerLayer.backgroundColor = UIColor.clear.cgColor
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: TransparentPlayerSurface, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    static func dismantleUIView(_ view: TransparentPlayerSurface, coordinator: ()) {
        view.playerLayer.player = nil
    }
}

final class TransparentPlayerSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
