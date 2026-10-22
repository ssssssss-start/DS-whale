import SpriteKit

final class CharacterScene: SKScene {
    let interaction = Interaction()
    let feedback = AudioFeedback()
    let character: SKSpriteNode
    let base: SKTexture
    let closed: SKTexture
    let eyeOverlay: SKSpriteNode
    private let waveFrames: [SKTexture]
    private let waveMotion: WaveMotion
    private let emotions = EmotionFrames()
    private let rig = SKNode()
    private let tailRig: TailRig
    private var nextBlink: TimeInterval = 0
    private var blinkStarted: TimeInterval?
    private var playedSerial = 0
    private var silentSerial = -1
    private var waveRecovery: WaveRecovery?
    private var headpatStartClosure = 0.0
    private(set) var eyeClosure = 0.0
    var idleMotion = !UserDefaults.standard.bool(forKey: "idleMotionDisabled")
    var onInteraction: (() -> Void)?
    var speakingLevel = 0.0
    var callPhase = "idle"
    var headpatHeld = false
    var lastTime: TimeInterval = 0
    var previewTime: TimeInterval?
    private let columns = 24
    private let rows = 26
    private var meshPoints: [SIMD2<Float>] = []
    private(set) var artRect = CGRect.zero

    init(size: CGSize, frames: [SKTexture]) {
        precondition(frames.count == 5)
        let base = frames[0], closed = frames[2]
        self.base = base
        self.closed = closed
        waveFrames = frames
        waveMotion = WaveMotion(size: base.size())
        tailRig = TailRig(base:base)
        character = SKSpriteNode(texture: base)
        character.zPosition = 1
        character.subdivisionLevels = 0
        eyeOverlay = SKSpriteNode(texture: closed)
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        addChild(rig)
        rig.addChild(tailRig.node)
        rig.addChild(character)
        // Put the blend boundary in the hair, outside all eye and eyebrow outlines.
        let crop = SKCropNode()
        let mask = SKSpriteNode(color:.white,size:base.size())
        mask.shader = SKShader(source:"""
        void main() {
            float d = length((v_tex_coord - vec2(0.475, 0.60)) / vec2(0.22, 0.145));
            float a = 1.0 - smoothstep(0.82, 1.0, d);
            a *= smoothstep(0.295, 0.308, v_tex_coord.x);
            gl_FragColor = vec4(a, a, a, a);
        }
        """)
        crop.maskNode = mask
        crop.addChild(eyeOverlay)
        crop.zPosition = 2
        rig.addChild(crop)
        eyeOverlay.alpha = 0
        for y in 0...rows {
            for x in 0...columns { meshPoints.append(SIMD2(Float(x) / Float(columns), Float(y) / Float(rows))) }
        }
        layoutArt()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func didChangeSize(_ oldSize: CGSize) { layoutArt() }
    private func layoutArt() {
        let room = CGRect(x: 9, y: 10, width: max(1, size.width - 18), height: max(1, size.height - 26))
        let factor = min(room.width / base.size().width, room.height / base.size().height)
        character.size = base.size()
        rig.setScale(factor)
        rig.position = CGPoint(x: room.midX, y: room.midY)
        eyeOverlay.size = base.size()
        artRect = CGRect(x: room.midX - base.size().width * factor / 2,
                         y: room.midY - base.size().height * factor / 2,
                         width: base.size().width * factor, height: base.size().height * factor)
    }
    func normalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - artRect.minX) / artRect.width, y: (point.y - artRect.minY) / artRect.height)
    }
    func isHead(_ point: CGPoint) -> Bool {
        let p = normalized(point)
        return p.x > 0.22 && p.x < 0.75 && p.y > 0.53 && p.y < 0.96
    }
    func request(_ behavior: Behavior) {
        let now = previewTime ?? ProcessInfo.processInfo.systemUptime
        guard interaction.begin(behavior, at: now, voiceDuration: feedback.duration(for: behavior)) else { return }
        if !behavior.isEmotion { onInteraction?() }
        feedback.stop()
        playNewInteraction(at:now)
    }
    func performBodyAction(_ behavior: Behavior) -> String {
        guard !isPaused else { return "unavailable" }
        let now = previewTime ?? ProcessInfo.processInfo.systemUptime
        interaction.advance(to:now)
        guard interaction.behavior == .idle || interaction.serial == silentSerial else { return "busy" }
        if behavior == .idle {
            headpatHeld = false; feedback.stop(); interaction.interrupt(at:now)
            return "accepted"
        }
        guard interaction.behavior == .idle, interaction.begin(behavior,at:now) else { return "busy" }
        // Agent gestures must not play bundled clips or cancel the live spoken reply.
        silentSerial = interaction.serial
        playNewInteraction(at:now)
        return "accepted"
    }
    private func playNewInteraction(at time: TimeInterval) {
        guard interaction.serial != playedSerial else { return }
        playedSerial = interaction.serial
        waveRecovery = nil
        headpatStartClosure = eyeClosure
        blinkStarted = nil
        nextBlink = time + 12.0
        if previewTime == nil && interaction.serial != silentSerial { feedback.play(interaction.behavior) }
    }
    func beginSpeaking() {
        feedback.stop()
        headpatHeld = false
        interaction.interrupt(at:previewTime ?? ProcessInfo.processInfo.systemUptime)
    }
    func suspend() {
        feedback.stop()
        headpatHeld = false
        interaction.reset()
        blinkStarted = nil; eyeOverlay.alpha = 0; eyeClosure = 0; waveRecovery = nil
        isPaused = true
    }
    func resume() {
        isPaused = false
        nextBlink = 0
    }
    override func update(_ currentTime: TimeInterval) {
        let time = previewTime ?? ProcessInfo.processInfo.systemUptime
        lastTime = time
        if headpatHeld { interaction.holdHeadPat(at:time) }
        interaction.advance(to: time)
        playNewInteraction(at:time)
        let behavior = interaction.behavior
        let elapsed = interaction.elapsed(at: time)
        let envelope = interaction.envelope(at: time)
        if nextBlink == 0 { nextBlink = time + 8.0 }
        if behavior != .idle { nextBlink = time + 12.0 }
        if behavior == .idle && time >= nextBlink {
            blinkStarted = time
            nextBlink = time + Double.random(in: 14.0...22.0)
        }
        var blink = 0.0
        if let start = blinkStarted {
            let t = time - start
            if t < IdleSmileTiming.duration { blink = IdleSmileTiming.closure(at:t) }
            else { blinkStarted = nil }
        }
        eyeClosure = behavior == .headpat
            ? envelope + headpatStartClosure * (1 - expressionEase(elapsed / behavior.entryDuration)) : blink
        // Reuse registered inbetweens inside the eyes, instead of dissolving two faces.
        if eyeClosure > 0 {
            eyeOverlay.texture = waveMotion.faceTexture(for:eyeClosure,frames:waveFrames)
            // The closed drawing has wider-set eyes and a slightly higher face.
            let align = max(0,(eyeClosure - 0.15) / 0.85)
            eyeOverlay.xScale = CGFloat(1 - 0.12 * align)
            eyeOverlay.position = CGPoint(x:base.size().width * 0.0085 * align,y:-base.size().height * 0.009 * align)
            eyeOverlay.alpha = 1
        } else { eyeOverlay.alpha = 0 }
        let greeting = behavior == .greeting
        let duration = interaction.duration
        let attention = callPhase == "listening" ? sin(time * 1.8) * 0.007
            : ["thinking","waiting","generating"].contains(callPhase) ? sin(time * 1.2) * 0.018 : 0
        rig.zRotation = CGFloat(sin(time * 3.4) * speakingLevel * 0.008 + attention)
        tailRig.update(time:time,enabled:idleMotion,headpat:behavior == .headpat ? envelope : 0,greetingElapsed:greeting ? elapsed : nil)
        if greeting {
            // Each pose is the complete supplied drawing, including shoulder, hand and expression.
            eyeOverlay.alpha = 0
            character.warpGeometry = nil
            eyeOverlay.warpGeometry = nil
            rig.position.y = artRect.midY
            let pose: WavePose
            if let start = interaction.recoveryStarted, time >= start {
                if waveRecovery == nil { waveRecovery = WaveRecovery(from:WavePose.at(start - interaction.started, duration:duration)) }
                pose = waveRecovery!.at((time - start) / (interaction.ends - start))
            } else { pose = WavePose.at(elapsed, duration:duration) }
            waveMotion.apply(pose, frames: waveFrames, to: character)
            if elapsed < 0.30, let texture = character.texture { character.texture = tailRig.bodyTexture(texture) }
            return
        }
        character.shader = nil
        character.texture = tailRig.bodyTexture(emotions.texture(behavior,level:envelope) ?? base)
        if behavior.isEmotion { eyeOverlay.alpha = 0 }
        var destinations = meshPoints
        let active = idleMotion ? 1.0 : 0.0
        let breath = sin(time * 1.65) * 0.0023 * active
        let idleTilt = sin(time * 0.68) * 0.0035 * active
        let tilt: Double
        switch behavior {
        case .poke: tilt = idleTilt * (1-envelope) + sin(elapsed * 4.2) * exp(-elapsed * 1.2) * 0.045 * envelope
        case .headpat: tilt = idleTilt * (1-envelope) + sin(elapsed * 1.8) * 0.025 * envelope
        case .greeting: tilt = 0
        case .shy: tilt = 0.018 * envelope
        case .surprised: tilt = sin(elapsed * 5) * exp(-elapsed * 2) * 0.012 * envelope
        case .sad: tilt = -0.012 * envelope
        case .sleepy: tilt = sin(elapsed * 0.85) * 0.022 * envelope
        case .idle: tilt = idleTilt
        }
        for index in destinations.indices {
            let p = meshPoints[index]
            let x = Double(p.x), y = Double(p.y)
            var dx = 0.0, dy = 0.0
            let head = smooth(0.46, 0.61, y)
            dx -= (y - 0.54) * tilt * head
            dy += (x - 0.46) * tilt * head
            dy += breath * smooth(0.09, 0.45, y)
            if behavior == .sleepy || behavior == .sad { dy -= 0.004 * head * envelope }
            let hair = (1 - smooth(0.28, 0.39, x) + smooth(0.62, 0.77, x))
                * smooth(0.18, 0.36, y) * (1 - smooth(0.66, 0.83, y))
            dx += sin(time * 1.35 + y * 5) * 0.005 * hair * active
            if behavior == .poke {
                let shoulders = exp(-pow((x - 0.46) / 0.24, 2) - pow((y - 0.43) / 0.10, 2))
                let flinch = max(0, sin(elapsed * 8)) * exp(-elapsed * 2) * envelope
                dx -= (x - 0.46) * shoulders * flinch * 0.05
                dy += shoulders * flinch * 0.008
            }
            // The tail is baked into the full-body image. Keep its shared lower-right
            // mesh cells still until separate artwork can preserve its attachment.
            let aboveTail = smooth(0.36, 0.45, y)
            let leftOfTail = 1 - smooth(0.58, 0.65, x)
            let movable = max(aboveTail, leftOfTail)
            destinations[index] = SIMD2(Float(x + dx * movable), Float(y + dy * movable))
        }
        let mesh = SKWarpGeometryGrid(columns: columns, rows: rows, sourcePositions: meshPoints, destinationPositions: destinations)
        character.warpGeometry = mesh
        // Overlays use the same deformation, keeping the expression attached to the face.
        eyeOverlay.warpGeometry = mesh
        if behavior == .poke {
            rig.position.y = artRect.midY + CGFloat(max(0, sin(elapsed * 8)) * exp(-elapsed * 2) * 4)
        } else { rig.position.y = artRect.midY }
    }
    private func smooth(_ low: Double, _ high: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - low) / (high - low)))
        return t * t * (3 - 2 * t)
    }
}
