import SpriteKit
import SceneKit
import Metal

// This preview follows the real desktop composition, rather than SCNRenderer alone.
func exportWhale3DComposite(modelURL: URL, output: URL) throws {
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    for (name,clip,time,dark) in [("front-light","Idle",0.0,false),("front-dimmed-whites","Idle",0.0,false),("front-dark","Idle",0.0,true),("side-light","Turn_360",2.0,false),("back-light","Turn_360",4.0,false),("wave-light","Wave",2.0,false)] {
        let whale = try Whale3D(url:modelURL)
        if name == "front-dimmed-whites" { whale.setWhiteBrightness(70) }
        let size = CGSize(width:430,height:530)
        let scene = SKScene(size:size)
        let background = SKSpriteNode(color:dark ? NSColor(white:0.10,alpha:1) : .white,size:size)
        background.position = CGPoint(x:size.width/2,y:size.height/2); background.zPosition = -1
        scene.addChild(background)
        let view = SKView(frame:CGRect(origin:.zero,size:size))
        view.allowsTransparency = true; view.isPaused = true
        whale.layout(size); whale.node.isPlaying = false
        whale.model.apply(clip,time:time,loop:false)
        scene.addChild(whale.node); view.presentScene(scene)
        SCNTransaction.flush()
        // SK3DNode allocates its offscreen target on the first SpriteKit draw.
        _ = view.texture(from:scene,crop:CGRect(origin:.zero,size:size))
        guard let texture = view.texture(from:scene,crop:CGRect(origin:.zero,size:size)) else { throw WhaleGLB.LoadError.invalid("SpriteKit composite") }
        let rep = NSBitmapImageRep(cgImage:texture.cgImage())
        guard let png = rep.representation(using:.png,properties:[:]) else { throw WhaleGLB.LoadError.invalid("Composite PNG") }
        try png.write(to:output.appendingPathComponent(name+".png"))
    }
    print("Saved desktop-path previews on light/dark backgrounds, including side, back and wave")
}

final class Whale3D {
    let model: WhaleGLB
    let node: SK3DNode
    let camera = SCNNode()
    var previewClip: String?
    var previewStarted: TimeInterval = 0

    init(url: URL) throws {
        model = try WhaleGLB(url:url)
        node = SK3DNode(viewportSize:CGSize(width:380,height:468))
        let scene = model.scene
        scene.background.contents = NSColor.clear
        camera.camera = SCNCamera(); camera.camera!.usesOrthographicProjection = true
        camera.camera!.orthographicScale = 1.12
        camera.camera!.wantsHDR = true
        // Keep the chosen brightness stable while the character moves or turns.
        camera.camera!.wantsExposureAdaptation = false
        camera.camera!.exposureOffset = 0.03
        camera.camera!.zNear = 0.01; camera.camera!.zFar = 20
        camera.position = SCNVector3(-0.05,0.95,5)
        camera.look(at:SCNVector3(-0.05,0.95,0))
        scene.rootNode.addChildNode(camera)
        // The supplied color map already includes painted shading and highlights.
        // Avoid adding a second metallic lighting pass over that artwork.
        scene.rootNode.enumerateChildNodes { node,_ in
            for material in node.geometry?.materials ?? [] {
                material.lightingModel = .constant
                material.normal.contents = nil
                material.specular.contents = NSColor.black
                // Match the painted colors through SK3DNode's linear compositing output.
                material.shaderModifiers = [.fragment: """
                    #pragma arguments
                    float whaleWhiteBrightness;
                    #pragma body
                    float3 painted = pow(max(_output.color.rgb, float3(0.0)), float3(1.0 / 2.2));
                    float high = max(painted.r, max(painted.g, painted.b));
                    float low = min(painted.r, min(painted.g, painted.b));
                    float saturation = (high - low) / max(high, 0.001);
                    float coolWhite = 1.0 - smoothstep(0.0, 0.02, painted.r - painted.b);
                    float whiteMask = coolWhite * (1.0 - smoothstep(0.04, 0.14, saturation)) * smoothstep(0.55, 0.85, low);
                    _output.color.rgb = painted * mix(1.0, whaleWhiteBrightness, whiteMask);
                    """]
                material.setValue(NSNumber(value:1.0), forKey:"whaleWhiteBrightness")
            }
        }
        node.scnScene = scene; node.pointOfView = camera
        node.autoenablesDefaultLighting = false; node.isPlaying = true
        node.zPosition = 5
    }
    func setWhiteBrightness(_ percent: Double) {
        let amount = max(0.5, min(1, percent / 100))
        model.scene.rootNode.enumerateChildNodes { node,_ in
            for material in node.geometry?.materials ?? [] {
                material.setValue(NSNumber(value:amount), forKey:"whaleWhiteBrightness")
            }
        }
    }
    func layout(_ size: CGSize) {
        node.position = CGPoint(x:size.width/2,y:size.height/2)
        node.viewportSize = size
    }
    func update(time: TimeInterval, behavior: Behavior, elapsed: TimeInterval, phase: String, speaking: Double, idleMotion: Bool) {
        let clip: String, clock: TimeInterval, loop: Bool
        if let previewClip, time-previewStarted < 8 {
            clip = previewClip; clock = time-previewStarted; loop = previewClip != "Turn_360"
        } else {
            previewClip = nil
            if behavior == .greeting { clip = "Wave"; clock = min(4,elapsed); loop = false }
            else if ["thinking","waiting","generating"].contains(phase) || behavior == .shy { clip = "Thinking"; clock = time; loop = true }
            else if phase == "listening" || behavior == .poke { clip = "Listening"; clock = time; loop = true }
            else { clip = "Idle"; clock = idleMotion ? time : 0; loop = true }
        }
        model.apply(clip,time:clock,loop:loop)
        let blinkPhase = time.truncatingRemainder(dividingBy:5)
        let blink = blinkPhase < 0.18 ? sin(blinkPhase / 0.18 * .pi) : 0
        model.morph("Blink",value:behavior == .sleepy || behavior == .headpat ? 0.7 : blink)
        model.morph("Mouth_A",value:speaking)
    }
}

func exportWhale3DPreview(modelURL: URL, output: URL) throws {
    let whale = try Whale3D(url:modelURL)
    guard let device = MTLCreateSystemDefaultDevice() else { throw WhaleGLB.LoadError.invalid("Metal unavailable") }
    let renderer = SCNRenderer(device:device,options:nil)
    renderer.scene = whale.model.scene; renderer.pointOfView = whale.camera
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    for (name,clip,time) in [("front","Idle",0.0),("side","Turn_360",2.0),("back","Turn_360",4.0),("wave","Wave",2.0),("walk","Walk_In_Place",0.25)] {
        whale.model.apply(clip,time:time,loop:false)
        let image = renderer.snapshot(atTime:0,with:CGSize(width:640,height:780),antialiasingMode:.multisampling4X)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data:tiff), let png = rep.representation(using:.png,properties:[:]) else { throw WhaleGLB.LoadError.invalid("Snapshot") }
        try png.write(to:output.appendingPathComponent(name+".png"))
    }
    whale.model.apply("Idle",time:0,loop:false)
    for (name,morph) in [("blink","Blink"),("speaking","Mouth_A")] {
        whale.model.morph(morph,value:1)
        let image = renderer.snapshot(atTime:0,with:CGSize(width:640,height:780),antialiasingMode:.multisampling4X)
        guard let data = image.tiffRepresentation, let rep = NSBitmapImageRep(data:data), let png = rep.representation(using:.png,properties:[:]) else { throw WhaleGLB.LoadError.invalid("Morph snapshot") }
        try png.write(to:output.appendingPathComponent(name+".png"))
        whale.model.morph(morph,value:0)
    }
    print("3D renderer loaded \(whale.model.nodes.count) nodes and \(whale.model.clips.count) clips; rendered front, side, back, wave and walk.")
}
