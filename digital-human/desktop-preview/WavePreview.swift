import AppKit
import SpriteKit
import ImageIO
import UniformTypeIdentifiers

func exportWavePreview(to folder: URL) throws {
    let url = Bundle.main.url(forResource: "wave-reference-full", withExtension: "png")!
    guard let artwork = FullBodyFrames(url: url) else { throw NSError(domain: "WhalePreview", code: 3) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let size = CGSize(width: 480, height: 560)
    let view = SKView(frame: CGRect(origin: .zero, size: size))
    view.allowsTransparency = true
    view.isPaused = true
    for (index, frame) in artwork.images.enumerated() {
        let output = folder.appendingPathComponent("pose-\(index).png")
        let png = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(png, frame, nil)
        CGImageDestinationFinalize(png)
    }
    let scene = CharacterScene(size: size, frames: artwork.textures)
    scene.previewTime = 0
    view.presentScene(scene)
    _ = scene.interaction.begin(.greeting, at: 0, voiceDuration: 3.072)
    scene.idleMotion = false
    let frameCount = Int(ceil((scene.interaction.ends + 0.8) * 30))
    let gif = CGImageDestinationCreateWithURL(folder.appendingPathComponent("wave.gif") as CFURL, UTType.gif.identifier as CFString, frameCount, nil)!
    CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for frame in 0..<frameCount {
        let time = Double(frame) / 30
        scene.previewTime = time
        scene.update(time)
        guard let rendered = view.texture(from: scene, crop: CGRect(origin: .zero, size: size)) else {
            throw NSError(domain: "WhalePreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render preview"])
        }
        let image = rendered.cgImage()
        CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary:
            [kCGImagePropertyGIFDelayTime: 1.0 / 30, kCGImagePropertyGIFUnclampedDelayTime: 1.0 / 30]] as CFDictionary)
        if [0, 8, 12, 16, 24, 40, 60, 80, 90, 119].contains(frame) {
            let output = folder.appendingPathComponent("frame-\(frame).png")
            let png = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(png, image, nil)
            CGImageDestinationFinalize(png)
        }
    }
    guard CGImageDestinationFinalize(gif) else { throw NSError(domain: "WhalePreview", code: 2) }
    print("Exported continuous wave preview: \(folder.path)")
}

func exportExpressionPreviews(to folder: URL, emotionsOnly: Bool = false) throws {
    if emotionsOnly { EmotionFrames().validate() }
    let url = Bundle.main.url(forResource:"wave-reference-full",withExtension:"png")!
    guard let artwork = FullBodyFrames(url:url) else { throw NSError(domain:"WhalePreview",code:3) }
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let samples: [(name: String, behavior: Behavior, interrupt: Double?, duration: Double)] = emotionsOnly
        ? Behavior.emotions.map { ($0.rawValue,$0,nil,$0.minimumDuration + 0.6) } + [("shy-reply",.shy,1.2,4.7)] : [
        ("headpat",.headpat,nil,5.4),
        ("headpat-light",.headpat,nil,5.4),
        ("headpat-dark",.headpat,nil,5.4),
        ("headpat-reply",.headpat,0.7,5.4),
        ("wave-reply",.greeting,4.5,7.4),
        ("idle-smile",.idle,nil,12.0),
        ("headpat-held",.headpat,nil,9.0)
    ]
    for sample in samples {
        let size = CGSize(width:380,height:468)
        let view = SKView(frame:CGRect(origin:.zero,size:size))
        view.allowsTransparency = true; view.isPaused = true
        let scene = CharacterScene(size:size,frames:artwork.textures)
        if sample.name == "headpat-light" { scene.backgroundColor = .white }
        if sample.name == "headpat-dark" { scene.backgroundColor = NSColor(calibratedRed:0.04,green:0.05,blue:0.08,alpha:1) }
        scene.previewTime = 0; scene.idleMotion = false
        view.presentScene(scene)
        if emotionsOnly {
            var stoppedVoice = false
            scene.onInteraction = { stoppedVoice = true }
            scene.request(sample.behavior)
            assert(!stoppedVoice,"Previewing an emotion must not stop call speech")
        } else { _ = scene.interaction.begin(sample.behavior,at:0) }
        let count = Int(sample.duration * 30)
        let gif = CGImageDestinationCreateWithURL(folder.appendingPathComponent(sample.name + ".gif") as CFURL,UTType.gif.identifier as CFString,count,nil)!
        CGImageDestinationSetProperties(gif,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
        var interrupted = false
        for frame in 0..<count {
            let time = Double(frame) / 30
            scene.previewTime = time
            scene.headpatHeld = sample.name == "headpat-held" && time < 5.5
            if sample.name == "idle-smile" && time >= 8.6 && time <= 10.5 {
                scene.update(time)
                assert(scene.eyeClosure > 0.99,"An idle smile must remain visible for two seconds")
            }
            if let when = sample.interrupt, time >= when, !interrupted {
                scene.update(time)
                let closure = scene.eyeClosure
                scene.beginSpeaking(); scene.update(time)
                assert(abs(scene.eyeClosure - closure) < 0.001,"A reply cannot snap the current face")
                interrupted = true
            }
            scene.update(time)
            if sample.behavior.isEmotion {
                if time >= 0.75 && time <= 3 { assert(scene.interaction.envelope(at:time) > 0.99) }
                if time >= sample.behavior.minimumDuration { assert(scene.interaction.behavior == .idle) }
            }
            if sample.behavior == .headpat {
                if time >= 0.6, time <= 3.4 { assert(scene.eyeClosure > 0.99,"Hold the full smile even during a reply") }
                if sample.name == "headpat-held", time >= 0.6 && time <= 6.9 { assert(scene.eyeClosure > 0.99) }
                if sample.name != "headpat-held", time >= (sample.interrupt == nil ? 4.8 : 4.5) { assert(scene.eyeClosure < 0.001,"Return fully to open eyes") }
            }
            guard let rendered = view.texture(from:scene,crop:CGRect(origin:.zero,size:size)) else { throw NSError(domain:"WhalePreview",code:1) }
            let image = rendered.cgImage()
            CGImageDestinationAddImage(gif,image,[kCGImagePropertyGIFDictionary:
                [kCGImagePropertyGIFDelayTime:1.0/30,kCGImagePropertyGIFUnclampedDelayTime:1.0/30]] as CFDictionary)
            if [0,15,54,72,90,120].contains(frame) {
                let png = CGImageDestinationCreateWithURL(folder.appendingPathComponent("\(sample.name)-\(frame).png") as CFURL,UTType.png.identifier as CFString,1,nil)!
                CGImageDestinationAddImage(png,image,nil)
                guard CGImageDestinationFinalize(png) else { throw NSError(domain:"WhalePreview",code:2) }
            }
        }
        guard CGImageDestinationFinalize(gif) else { throw NSError(domain:"WhalePreview",code:2) }
    }
    if emotionsOnly {
        let width = 1440, height = 520
        let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray:0.96,alpha:1)); context.fill(CGRect(x:0,y:0,width:width,height:height))
        for (index,behavior) in Behavior.emotions.enumerated() {
            let imageURL = folder.appendingPathComponent(behavior.rawValue+"-54.png")
            let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(imageURL as CFURL,nil)!,0,nil)!
            context.draw(image,in:CGRect(x:index*360+15,y:48,width:330,height:406))
            let text = NSAttributedString(string:behavior.title,attributes:[.font:NSFont.systemFont(ofSize:22),.foregroundColor:NSColor.darkGray])
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:false)
            text.draw(at:CGPoint(x:index*360+110,y:15))
            NSGraphicsContext.restoreGraphicsState()
        }
        let png = CGImageDestinationCreateWithURL(folder.appendingPathComponent("expressions.png") as CFURL,UTType.png.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(png,context.makeImage()!,nil); precondition(CGImageDestinationFinalize(png))
    }
    print("Exported expression checks: readable holds, smooth recovery and rendered previews (no voice API).")
}

func exportTailPreview(to folder: URL) throws {
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let source = Bundle.main.url(forResource:"wave-reference-full",withExtension:"png")!
    let art = FullBodyFrames(url:source)!
    TailRig(base:art.textures[0]).exportLayers(base:art.textures[0],to:folder)
    let size = CGSize(width:432,height:534)
    let view = SKView(frame:CGRect(origin:.zero,size:size))
    view.allowsTransparency = true; view.isPaused = true
    let scene = CharacterScene(size:size,frames:art.textures)
    scene.previewTime = 0; scene.idleMotion = true
    view.presentScene(scene)
    let gif = CGImageDestinationCreateWithURL(folder.appendingPathComponent("tail.gif") as CFURL,UTType.gif.identifier as CFString,144,nil)!
    CGImageDestinationSetProperties(gif,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
    // Warm the amplitude envelope before recording a closed 4.8-second loop.
    for i in 0..<144 { scene.previewTime = Double(i)/30; scene.update(Double(i)/30) }
    for i in 0..<144 {
        let t = 4.8+Double(i)/30
        scene.previewTime = t; scene.update(t)
        let image = view.texture(from:scene,crop:CGRect(origin:.zero,size:size))!.cgImage()
        CGImageDestinationAddImage(gif,image,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:1.0/30,kCGImagePropertyGIFUnclampedDelayTime:1.0/30]] as CFDictionary)
        if [0,36,72,108].contains(i) {
            let png = CGImageDestinationCreateWithURL(folder.appendingPathComponent("tail-\(i).png") as CFURL,UTType.png.identifier as CFString,1,nil)!
            CGImageDestinationAddImage(png,image,nil); precondition(CGImageDestinationFinalize(png))
        }
    }
    precondition(CGImageDestinationFinalize(gif))
    print("Exported tail preview (no voice API): \(folder.path)")
}
