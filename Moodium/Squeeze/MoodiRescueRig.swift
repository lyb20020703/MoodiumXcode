import Foundation
import SceneKit
import simd

// Moodi squeezed out of the pillow, for the phone app (SceneKit).
//
// Assets (Resources/Models):
//   Moodi.usdz                 Moodi v2, 19 bones
//   <Soft>_Mouth.usdz          the pillow with the opening + throat, 25 mouth bones
//   <Soft>_MoodiTracks.json    every clip of both rigs, baked per frame
// Both USDZ share one frame: rig units (Moodi is 1.83 tall), Y up, the mouth centre at the origin,
// Moodi facing +Z. So the two files are simply siblings under `node`.
//
// This file only uses SceneKit + simd, so it builds for iOS and for the macOS preview tool.

// MARK: - Baked clips

struct MoodiTracks: Decodable {
    struct Rig: Decodable {
        let bones: [String]
        let parents: [String?]
        let rest: [[Float]]
        let clips: [String: Clip]
    }

    struct Clip: Decodable {
        let frames: [[[Float]]]
    }

    let fps: Float
    let moodi: Rig
    let mouth: Rig
}

struct BonePose {
    var t: SIMD3<Float>
    var q: simd_quatf
    var s: SIMD3<Float>

    init(_ r: [Float]) {
        t = SIMD3(r[0], r[1], r[2])
        q = simd_normalize(simd_quatf(ix: r[3], iy: r[4], iz: r[5], r: r[6]))
        s = SIMD3(r[7], r[8], r[9])
    }

    init(t: SIMD3<Float>, q: simd_quatf, s: SIMD3<Float>) {
        self.t = t; self.q = q; self.s = s
    }

    static func mix(_ a: BonePose, _ b: BonePose, _ w: Float) -> BonePose {
        BonePose(t: simd_mix(a.t, b.t, SIMD3(repeating: w)), q: simd_slerp(a.q, b.q, w), s: simd_mix(a.s, b.s, SIMD3(repeating: w)))
    }

    var matrix: simd_float4x4 {
        var m = simd_float4x4(q)
        m.columns.0 *= s.x
        m.columns.1 *= s.y
        m.columns.2 *= s.z
        m.columns.3 = SIMD4(t, 1)
        return m
    }
}

typealias RigPose = [BonePose]

func mixPose(_ a: RigPose, _ b: RigPose, _ w: Float) -> RigPose {
    if w <= 0 { return a }
    if w >= 1 { return b }
    return zip(a, b).map { BonePose.mix($0, $1, w) }
}

/// Drives the bone nodes SceneKit created for one skeleton.
final class BoneRig {
    let data: MoodiTracks.Rig
    let fps: Float
    private let nodes: [SCNNode?]
    private let index: [String: Int]

    init(_ data: MoodiTracks.Rig, fps: Float, under root: SCNNode) {
        self.data = data
        self.fps = fps
        nodes = data.bones.map { root.childNode(withName: $0, recursively: true) }
        index = Dictionary(uniqueKeysWithValues: data.bones.enumerated().map { ($1, $0) })
    }

    var missingBones: [String] { zip(data.bones, nodes).filter { $1 == nil }.map { $0.0 } }
    func boneIndex(_ name: String) -> Int? { index[name] }
    func frameCount(_ clip: String) -> Int { data.clips[clip]?.frames.count ?? 0 }
    func duration(_ clip: String) -> Float { Float(max(0, frameCount(clip) - 1)) / fps }

    /// Pose at a (fractional) frame, clamped to the clip.
    func sample(_ clip: String, frame: Float) -> RigPose {
        guard let frames = data.clips[clip]?.frames, !frames.isEmpty else { return rest }
        let f = max(0, min(Float(frames.count - 1), frame))
        let i = Int(f.rounded(.down)), j = min(i + 1, frames.count - 1), w = f - Float(i)
        return zip(frames[i], frames[j]).map { BonePose.mix(BonePose($0), BonePose($1), w) }
    }

    func sample(_ clip: String, time: Float, loop: Bool) -> RigPose {
        let n = Float(frameCount(clip) - 1)
        var f = time * fps
        if loop, n > 0 { f = f.truncatingRemainder(dividingBy: n) }
        return sample(clip, frame: f)
    }

    var rest: RigPose { data.rest.map(BonePose.init) }

    /// base ⊕ weight × (frame 1 − frame 0) of a two-frame additive clip (Strain, Mouth_Pucker).
    func addAdditive(_ base: RigPose, clip: String, weight: Float) -> RigPose {
        guard weight != 0, let fr = data.clips[clip]?.frames, fr.count >= 2 else { return base }
        return base.enumerated().map { k, b in
            let p0 = BonePose(fr[0][k]), p1 = BonePose(fr[1][k])
            let dq = simd_slerp(simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), simd_normalize(p0.q.inverse * p1.q), weight)
            let ds = SIMD3<Float>(repeating: 1) + (p1.s / p0.s - 1) * weight
            return BonePose(t: b.t + (p1.t - p0.t) * weight, q: simd_normalize(b.q * dq), s: b.s * ds)
        }
    }

    func apply(_ pose: RigPose) {
        for (node, p) in zip(nodes, pose) { node?.simdTransform = p.matrix }
    }

    /// Armature-space rest rotation of a bone (for picking the eye's vertical axis).
    func restRotation(_ name: String) -> simd_quatf {
        var q = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        var current: String? = name
        while let n = current, let k = index[n] {
            q = BonePose(data.rest[k]).q * q
            current = data.parents[k]
        }
        return q
    }
}

// MARK: - Springs (same numbers as the visionOS display)

/// SqueezeProgressVideoController.StepSpring: stiff and damped while held, bouncy on release,
/// plus a kick of 2.5 on every new press.
struct PressSpring {
    var s: Float = 0, v: Float = 0
    private var held = false

    mutating func step(held h: Bool, dt: Float) -> Float {
        if h && !held { v += 2.5 }
        held = h
        let (k, z): (Float, Float) = h ? (2500, 0.85) : (220, 0.32)
        let target: Float = h ? 1 : 0
        let n = 16, step = dt / Float(n)
        for _ in 0..<n {
            let a = -k * (s - target) - 2 * z * k.squareRoot() * v
            v += a * step
            s += v * step
        }
        return s
    }
}

/// Unity's Mathf.SmoothDamp.
func smoothDamp(_ current: Float, _ target: Float, _ velocity: inout Float, smoothTime: Float, maxSpeed: Float, dt: Float) -> Float {
    let st = max(0.0001, smoothTime), omega = 2 / st, x = omega * dt
    let exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
    let maxChange = maxSpeed * st
    let change = max(-maxChange, min(maxChange, current - target))
    let t2 = current - change
    let temp = (velocity + omega * change) * dt
    velocity = (velocity - omega * temp) * exp
    var out = t2 + (change + temp) * exp
    if (target - current > 0) == (out > target) {
        out = target
        velocity = dt > 0 ? (out - target) / dt : 0
    }
    return out
}

// MARK: - The rescue rig

/// Owns the pillow-with-mouth and Moodi for one world and plays the whole squeeze-out:
/// fly in → fall into the opening → peek (muffled lines) → squeezed out with the energy → pop → jump out.
///
/// Call `update(dt:)` once per rendered frame (SoftStage's renderer(_:updateAtTime:)).
/// Everything is in rig units under `node`; SoftStage scales and tilts `node` onto the screen.
final class MoodiRescueRig {
    enum Phase: Equatable { case waiting, flyingIn, fallingIn, peeking, emerging, popping, free, leaving }

    let node = SCNNode()
    let softNode: SCNNode
    let moodiNode: SCNNode
    /// Bounding box of the pillow body alone (no Moodi, no throat), for fitting it on screen.
    let softBounds: (min: SIMD3<Float>, max: SIMD3<Float>)

    // Tunables (the visionOS defaults)
    var smoothTime: Float = 0.25
    var maxSpeed: Float = 0.3
    var popThreshold: Float = 0.995
    /// Where Moodi floats after jumping out, in rig units (up = out of the mouth, +Z = Moodi's front).
    var hoverPoint = SIMD3<Float>(0, 2.3, 1.3)
    var hoverScale: Float = 1.25
    /// Where Moodi stops to wave before slipping into the opening.
    var waveAbove = SIMD3<Float>(0.4, 2.5, 0.5)
    var jumpDuration: Float = 0.6
    /// How loud Moodi is talking while stuck (0…1); drives the sprout wiggle in Peek.
    var talk: Float = 0

    var onSplash: (() -> Void)?
    var onPop: (() -> Void)?
    /// Fired once Moodi has landed in the hover point after the jump.
    var onFree: (() -> Void)?

    private(set) var phase: Phase = .waiting
    private(set) var progress: Float = 0
    private var target: Float = 0
    private var velocity: Float = 0
    private var spring = PressSpring()
    private var pressS: Float = 0
    private var heldByTouch = false
    private var pulseLeft: Float = 0
    private var phaseTime: Float = 0
    private var clock: Float = 0
    private var blinks: [Float] = []
    private var fly: (from: SIMD3<Float>, fly: Float, wave: Float, drop: Float) = (.zero, 0.9, 0.8, 0.35)
    private var lastMoodiPose: RigPose = []

    private let moodiRig: BoneRig
    private let mouthRig: BoneRig
    private let eyes: [(Int, Int)]   // bone index, axis to squash

    /// Loads one world. Do this off the main thread (USDZ + JSON ≈ 0.3 s).
    init?(softURL: URL, moodiURL: URL, tracksURL: URL) {
        guard let softScene = try? SCNScene(url: softURL, options: [.checkConsistency: false]),
              let moodiScene = try? SCNScene(url: moodiURL, options: [.checkConsistency: false]),
              let data = try? Data(contentsOf: tracksURL),
              let tracks = try? JSONDecoder().decode(MoodiTracks.self, from: data) else { return nil }
        let softHolder = SCNNode(), moodiHolder = SCNNode()
        for child in softScene.rootNode.childNodes { softHolder.addChildNode(child) }
        for child in moodiScene.rootNode.childNodes { moodiHolder.addChildNode(child) }
        softNode = softHolder
        moodiNode = moodiHolder
        node.addChildNode(softNode)
        node.addChildNode(moodiNode)

        moodiRig = BoneRig(tracks.moodi, fps: tracks.fps, under: moodiNode)
        mouthRig = BoneRig(tracks.mouth, fps: tracks.fps, under: softNode)
        guard moodiRig.missingBones.isEmpty, mouthRig.missingBones.isEmpty else { return nil }

        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        let container = node
        softNode.enumerateHierarchy { n, _ in
            guard n.geometry != nil, n.skinner == nil, let name = n.parent?.name ?? n.name, name.hasSuffix("_Static") else { return }
            let (a, b) = n.boundingBox
            for x in [a.x, b.x] { for y in [a.y, b.y] { for z in [a.z, b.z] {
                let w = n.simdConvertPosition(SIMD3<Float>(Float(x), Float(y), Float(z)), to: container)
                lo = simd_min(lo, w); hi = simd_max(hi, w)
            } } }
        }
        softBounds = (lo, hi)

        let rig = moodiRig
        eyes = ["Eye_L", "Eye_R"].compactMap { name in
            guard let k = rig.boneIndex(name) else { return nil }
            // the bone axis that points most along armature +Z (up) is the one a blink squashes
            let r = rig.restRotation(name)
            let x = abs(r.act(SIMD3(1, 0, 0)).z), z = abs(r.act(SIMD3(0, 0, 1)).z)
            return (k, x > z ? 0 : 2)
        }
        reset()
    }

    // MARK: Story calls

    /// Empty opening, Moodi hidden. Also the state for "again".
    func reset() {
        phase = .waiting
        progress = 0; target = 0; velocity = 0
        spring = PressSpring(); pressS = 0; pulseLeft = 0; heldByTouch = false
        blinks.removeAll()
        moodiNode.isHidden = true
        moodiNode.simdPosition = .zero
        moodiNode.simdOrientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        moodiNode.simdScale = SIMD3(repeating: 1)
        mouthRig.apply(mouthRig.sample("Mouth_Emerge", frame: 0))
    }

    /// Same beats as the 2D sprite: fly in from `start` (rig units, e.g. off the top-right of the screen),
    /// wave above the opening, slip and drop in. Contact (and `onSplash`) is at fly + wave + drop
    /// = 2.05 s by default, the same moment as the sprite, so K1 at 1.75 s still lands just before it.
    /// Then FallIn (0.5 s) sinks Moodi to the "only the sprout shows" pose.
    func fallIn(from start: SIMD3<Float>, flyDuration: Float = 0.9, waveDuration: Float = 0.8, dropDuration: Float = 0.35) {
        fly = (start, flyDuration, waveDuration, dropDuration)
        moodiNode.isHidden = false
        moodiNode.simdScale = SIMD3(repeating: 1)
        enter(.flyingIn)
    }

    /// "Again": Moodi floats up and away while the dimple opens back into the empty opening (0.45 s),
    /// then everything is as after `reset()`.
    func leave() {
        if phase == .free || phase == .popping { enter(.leaving) } else { reset() }
    }

    /// While the muffled K2 / K3 lines play; set `talk` from the voice level.
    func setPeeking(_ on: Bool) {
        if on, phase == .fallingIn || phase == .emerging { enter(.peeking) }
        if !on, phase == .peeking { enter(.emerging) }
    }

    /// Energy 0…1. Only ever goes up; smoothed like the visionOS display.
    func setProgress(_ p: Float) {
        target = max(target, max(0, min(1, p)))
        if phase == .peeking, target > 0 { enter(.emerging) }
    }

    /// One squeeze of the base: a short press of the spring.
    func squeeze(intensity: Float) {
        pulseLeft = 0.12 + 0.12 * max(0, min(1, intensity))
    }

    /// Touch mode: finger down / up.
    func setHeld(_ held: Bool) { heldByTouch = held }

    /// Quick blink (0.1 s shut, 0.1 s open). `count` 2 = the "I can see the light" double blink.
    func blink(count: Int = 1, delay: Float = 0) {
        for n in 0..<count { blinks.append(clock + delay + 0.3 * Float(n)) }
    }

    /// Skip the remaining smoothing and pop now (the 1.2 s fallback after 100 %).
    func forcePop() {
        if phase == .emerging || phase == .peeking { beginPop() }
    }

    // MARK: Per frame

    func update(dt rawDt: Float) {
        let dt = max(0, min(1.0 / 20, rawDt))
        clock += dt
        phaseTime += dt
        pulseLeft = max(0, pulseLeft - dt)
        let held = heldByTouch || pulseLeft > 0
        pressS = spring.step(held: held && (phase == .emerging || phase == .peeking), dt: dt)

        switch phase {
        case .waiting:
            break

        case .flyingIn:
            let t = phaseTime
            mouthRig.apply(mouthRig.sample("Mouth_Emerge", frame: 0))
            if t < fly.fly {
                // swoop in on a curve, slowing down above the opening
                let u = t / fly.fly, e = 1 - (1 - u) * (1 - u)
                let ctrl = SIMD3<Float>(fly.from.x * 0.4 + waveAbove.x * 0.6, max(fly.from.y, waveAbove.y) + 1.2, waveAbove.z)
                let a = simd_mix(fly.from, ctrl, SIMD3(repeating: e)), b = simd_mix(ctrl, waveAbove, SIMD3(repeating: e))
                moodiNode.simdPosition = simd_mix(a, b, SIMD3(repeating: e))
                setMoodi(moodiRig.sample("Idle", time: t, loop: true))
            } else if t < fly.fly + fly.wave {
                // hover and wave
                let tw = t - fly.fly
                moodiNode.simdPosition = waveAbove + SIMD3(0, 0.08 * sin(tw * 7), 0)
                setMoodi(mixPose(moodiRig.sample("Idle", time: t, loop: true), moodiRig.sample("Wave", time: tw, loop: false), min(1, tw / 0.12)))
            } else {
                // slip (a quick roll) and drop straight in, accelerating
                let u = min(1, (t - fly.fly - fly.wave) / fly.drop), e = u * u
                moodiNode.simdPosition = simd_mix(waveAbove, .zero, SIMD3(repeating: e))
                moodiNode.simdOrientation = simd_quatf(angle: 0.55 * sin(.pi * u), axis: SIMD3(0, 0, 1))
                let w = u * u * (3 - 2 * u)
                setMoodi(mixPose(moodiRig.sample("Touched", time: t - fly.fly - fly.wave, loop: true), moodiRig.sample("FallIn", frame: 0), w))
                if u >= 1 {
                    moodiNode.simdPosition = .zero
                    moodiNode.simdOrientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                    onSplash?()
                    enter(.fallingIn)
                }
            }

        case .fallingIn:
            let frames = Float(moodiRig.frameCount("FallIn") - 1)
            let f = min(frames, phaseTime * moodiRig.fps)
            let u = f / frames
            setMoodi(moodiRig.sample("FallIn", frame: f))
            let p = 0.35 * (1 - u) * (1 - u)
            var mouth = mouthRig.sample("Mouth_Emerge", frame: p * 90)
            mouth = mouthRig.addAdditive(mouth, clip: "Mouth_Pucker", weight: 0.6 * sin(.pi * u))
            mouthRig.apply(mouth)
            if u >= 1 { enter(.peeking) }

        case .peeking:
            let still = moodiRig.sample("Emerge", frame: 0)
            let wiggle = moodiRig.sample("Peek", time: phaseTime, loop: true)
            setMoodi(mixPose(still, wiggle, 0.3 + 0.7 * max(0, min(1, talk))))
            mouthRig.apply(mouthRig.sample("Mouth_Emerge", frame: 0))

        case .emerging:
            progress = smoothDamp(progress, target, &velocity, smoothTime: smoothTime, maxSpeed: maxSpeed, dt: dt)
            progress = min(progress, 1)
            let s = max(pressS, 0)
            var pose = moodiRig.sample("Emerge", frame: progress * 90)
            pose = moodiRig.addAdditive(pose, clip: "Strain", weight: s)   // includes the 0.26 lift while held
            if pressS < 0, let root = moodiRig.boneIndex("Root") { pose[root].t.z += 0.07 * pressS }  // sink on the rebound
            setMoodi(pose)
            var mouth = mouthRig.sample("Mouth_Emerge", frame: progress * 90)
            mouth = mouthRig.addAdditive(mouth, clip: "Mouth_Pucker", weight: s)
            mouthRig.apply(mouth)
            if progress >= popThreshold && target >= 1 { beginPop() }

        case .popping:
            mouthRig.apply(mouthRig.sample("Mouth_Pop", time: phaseTime, loop: false))
            let u = min(1, phaseTime / jumpDuration)
            let e = u * u * (3 - 2 * u)
            // arc: up out of the opening, then over to the hover point; one full turn on the way
            var p = simd_mix(SIMD3<Float>(0, 0, 0), hoverPoint, SIMD3(repeating: e))
            p.y += 1.2 * 4 * u * (1 - u)
            moodiNode.simdPosition = p
            moodiNode.simdOrientation = simd_quatf(angle: 2 * .pi * e, axis: SIMD3(0, 1, 0))
            moodiNode.simdScale = SIMD3(repeating: 1 + (hoverScale - 1) * e)
            let happy = moodiRig.sample("Happy", time: phaseTime, loop: false)
            setMoodi(mixPose(lastMoodiPose, happy, min(1, phaseTime / 0.1)), keep: false)
            if u >= 1 {
                blink(delay: 0.3)
                onFree?()
                enter(.free)
            }

        case .free:
            mouthRig.apply(mouthRig.sample("Mouth_Pop", time: 99, loop: false))
            let happyLeft = moodiRig.duration("Happy") - (phaseTime + jumpDuration)
            let idle = moodiRig.sample("Idle", time: phaseTime, loop: true)
            let pose = happyLeft > 0 ? moodiRig.sample("Happy", time: phaseTime + jumpDuration, loop: false)
                                     : mixPose(moodiRig.sample("Happy", frame: 999), idle, min(1, -happyLeft / 0.25))
            setMoodi(pose, keep: false)
            var p = hoverPoint
            p.y += 0.12 * sin(phaseTime * 2 * .pi / 1.8)
            moodiNode.simdPosition = p
            moodiNode.simdOrientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

        case .leaving:
            let u = min(1, phaseTime / 0.45), e = u * u * (3 - 2 * u)
            moodiNode.simdPosition = hoverPoint + SIMD3(0, 2.5 * u * u, 0)
            moodiNode.simdScale = SIMD3(repeating: max(0.001, hoverScale * (1 - e)))
            setMoodi(moodiRig.sample("Idle", time: clock, loop: true), keep: false)
            mouthRig.apply(mixPose(mouthRig.sample("Mouth_Pop", frame: 999), mouthRig.sample("Mouth_Emerge", frame: 0), e))
            if u >= 1 { reset() }
        }
    }

    private func enter(_ p: Phase) {
        phase = p
        phaseTime = 0
    }

    private func beginPop() {
        progress = 1
        enter(.popping)
        onPop?()
    }

    private func setMoodi(_ pose: RigPose, keep: Bool = true) {
        var p = pose
        let b = blinkAmount()
        if b < 1 {
            for (k, axis) in eyes { p[k].s[axis] *= b }
        }
        if keep { lastMoodiPose = pose }
        moodiRig.apply(p)
    }

    private func blinkAmount() -> Float {
        var a: Float = 1
        for t0 in blinks {
            let t = clock - t0
            if t >= 0 && t < 0.2 {
                let closed: Float = 0.08
                a = min(a, t < 0.1 ? 1 - (1 - closed) * (t / 0.1) : closed + (1 - closed) * ((t - 0.1) / 0.1))
            }
        }
        blinks.removeAll { clock - $0 > 0.5 }
        return a
    }
}
