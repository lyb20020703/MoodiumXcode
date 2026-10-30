import AVFoundation

/// Background music, sound effects and Moodi's voice.
/// Voice runs through a low-pass filter so Moodi sounds muffled while stuck in the jelly
/// and clearer as the squeeze energy rises (as in the visionOS squeeze rescue).
final class AudioDirector {
    static let shared = AudioDirector()

    var muted = false {
        didSet {
            bgm?.volume = muted ? 0 : bgmVolume
            engine.mainMixerNode.outputVolume = muted ? 0 : 1
        }
    }

    private var bgm: AVAudioPlayer?
    private var bgmVolume: Float = 0.38
    private var sfxPool: [String: [AVAudioPlayer]] = [:]

    private let engine = AVAudioEngine()
    private let voiceNode = AVAudioPlayerNode()
    private let filter = AVAudioUnitEQ(numberOfBands: 1)
    private var voiceFormat: AVAudioFormat?
    private var voiceToken = 0
    private(set) var voiceLevel: Float = 0
    private var hasTap = false
    private(set) var isSpeaking = false

    private init() {
        engine.attach(voiceNode)
        engine.attach(filter)
        let band = filter.bands[0]
        band.filterType = .lowPass
        band.frequency = 20_000
        band.bypass = false
        filter.globalGain = 4
    }

    // MARK: Music

    func playMusic(_ name: String) {
        guard let url = Res.url(name, "mp3") else { return }
        if bgm?.url == url, bgm?.isPlaying == true { return }
        bgm?.stop()
        bgm = try? AVAudioPlayer(contentsOf: url)
        bgm?.numberOfLoops = -1
        bgm?.volume = 0
        bgm?.play()
        bgm?.setVolume(muted ? 0 : bgmVolume, fadeDuration: 2.0)
    }

    func stopMusic(fade: TimeInterval = 0.8) {
        guard let player = bgm else { return }
        player.setVolume(0, fadeDuration: fade)
        DispatchQueue.main.asyncAfter(deadline: .now() + fade) { [weak player] in player?.stop() }
        bgm = nil
    }

    func pauseAll() { bgm?.pause(); voiceNode.pause() }
    func resumeAll() { bgm?.play(); if engine.isRunning { voiceNode.play() } }

    private func duck(_ on: Bool) {
        guard !muted else { return }
        bgm?.setVolume(on ? bgmVolume * 0.45 : bgmVolume, fadeDuration: 0.3)
    }

    // MARK: Effects

    func sfx(_ name: String, volume: Float = 1, ext: String = "wav") {
        guard !muted, let url = Res.url(name, ext) else { return }
        var pool = sfxPool[name] ?? []
        let player: AVAudioPlayer
        if let idle = pool.first(where: { !$0.isPlaying }) {
            player = idle
        } else if pool.count < 4, let fresh = try? AVAudioPlayer(contentsOf: url) {
            fresh.prepareToPlay()
            pool.append(fresh)
            sfxPool[name] = pool
            player = fresh
        } else { return }
        player.currentTime = 0
        player.volume = volume
        player.play()
    }

    // MARK: Voice

    /// Plays a Moodi line. `clarity` 0 = deep inside the jelly, 1 = out in the open.
    /// Returns the line's duration in seconds.
    @discardableResult
    func voice(_ file: String, clarity: Double, completion: (() -> Void)? = nil) -> TimeInterval {
        guard let url = Res.url(file, "wav"), let audio = try? AVAudioFile(forReading: url) else {
            completion?()
            return 0
        }
        let duration = Double(audio.length) / audio.processingFormat.sampleRate
        if muted { completion?(); return duration }

        voiceNode.stop()
        if voiceFormat != audio.processingFormat {
            if engine.isRunning { engine.stop() }
            engine.disconnectNodeOutput(voiceNode)
            engine.disconnectNodeOutput(filter)
            engine.connect(voiceNode, to: filter, format: audio.processingFormat)
            engine.connect(filter, to: engine.mainMixerNode, format: audio.processingFormat)
            if hasTap { filter.removeTap(onBus: 0) }
            filter.installTap(onBus: 0, bufferSize: 1024, format: audio.processingFormat) { [weak self] buffer, _ in
                guard let channel = buffer.floatChannelData?[0] else { return }
                let n = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<n { sum += channel[i] * channel[i] }
                let level = min(1, (sum / Float(max(1,n))).squareRoot() * 6)
                DispatchQueue.main.async { guard let self else { return }; self.voiceLevel += (level - self.voiceLevel) * 0.5 }
            }
            hasTap = true
            voiceFormat = audio.processingFormat
        }
        let c = max(0, min(1, clarity))
        filter.bands[0].frequency = Float(900 + pow(c, 1.6) * 19_000)
        filter.bands[0].bypass = c >= 0.99
        if !engine.isRunning { try? engine.start() }

        voiceToken += 1
        let token = voiceToken
        isSpeaking = true
        duck(true)
        voiceNode.scheduleFile(audio, at: nil) { [weak self] in
            DispatchQueue.main.async {
                guard let self, token == self.voiceToken else { return }
                self.isSpeaking = false
                self.duck(false)
                completion?()
            }
        }
        voiceNode.play()
        return duration
    }

    func stopVoice() {
        voiceLevel = 0
        voiceToken += 1
        voiceNode.stop()
        isSpeaking = false
        duck(false)
    }
}
