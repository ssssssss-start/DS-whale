import simd
import ImageIO
import UniformTypeIdentifiers

import SpriteKit
import AppKit

struct TailPose {
    let rootAngle: Double
    let tipAngle: Double
    static func at(_ time: Double, strength: Double) -> TailPose {
        let phase = time * (2 * Double.pi / 4.8)
        return TailPose(rootAngle: sin(phase) * 0.032 * strength,
                        tipAngle: sin(phase - 0.55) * 0.025 * strength)
    }
    func point(_ p: SIMD2<Float>) -> SIMD2<Float> {
        let root = SIMD2<Double>(266, 90)
        let joint = SIMD2<Double>(353, 116)
        let original = SIMD2<Double>(Double(p.x) * 432, Double(p.y) * 534)
        func ease(_ x: Double) -> Double { let t = min(1,max(0,x)); return t*t*(3-2*t) }
        func rotate(_ p: SIMD2<Double>, around c: SIMD2<Double>, by a: Double) -> SIMD2<Double> {
            let d = p-c
            return c + SIMD2(cos(a)*d.x-sin(a)*d.y, sin(a)*d.x+cos(a)*d.y)
        }
        // The attachment is under the skirt; distal vertices share a rigid fluke rotation.
        let tipWeight = ease((original.x - 318) / 47)
        let rootWeight = ease((original.x - root.x) / 30)
        let bent = rotate(original,around:joint,by:tipAngle * tipWeight)
        let moved = rotate(bent,around:root,by:rootAngle * rootWeight)
        return SIMD2(Float(moved.x/432),Float(moved.y/534))
    }
}

final class TailRig {
    let node = SKNode()
    private let tail: SKSpriteNode
    private let rootFill: SKSpriteNode
    private let maskImage: CGImage
    private var bodyTextures: [ObjectIdentifier: SKTexture] = [:]
    private let points: [SIMD2<Float>]
    private var strength = 0.0
    private var lastTime: Double?
    private let columns = 24, rows = 26

    init(base: SKTexture) {
        let size = base.size()
        maskImage = Self.makeMask(base:base).cgImage()
        tail = SKSpriteNode(texture:Self.masked(base,mask:maskImage,keepTail:true))
        tail.size = size
        tail.subdivisionLevels = 0
        let rootURL = Bundle.main.url(forResource:"root-source",withExtension:"png",subdirectory:"tail-v1")
        rootFill = SKSpriteNode(texture:rootURL.flatMap { NSImage(contentsOf:$0) }.map { SKTexture(image:$0) })
        rootFill.size = size
        rootFill.subdivisionLevels = 0
        // Clip the reconstructed root before rendering; no live fragment mask is needed.
        if let texture = rootFill.texture {
            let c = CGContext(data:nil,width:432,height:534,bitsPerComponent:8,bytesPerRow:432*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.clip(to:CGRect(x:254,y:89,width:31,height:20))
            c.draw(texture.cgImage(),in:CGRect(x:0,y:0,width:432,height:534))
            rootFill.texture = SKTexture(cgImage:c.makeImage()!)
        }
        node.zPosition = 0
        node.addChild(rootFill); node.addChild(tail)
        let columns = 24, rows = 26
        points = (0...rows).flatMap { y in (0...columns).map { x in SIMD2(Float(x)/Float(columns),Float(y)/Float(rows)) } }
    }
    func exportLayers(base: SKTexture, to folder: URL) {
        func raster(_ images: [CGImage]) -> [UInt8] {
            let c = CGContext(data:nil,width:432,height:534,bitsPerComponent:8,bytesPerRow:432*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            for image in images { c.draw(image,in:CGRect(x:0,y:0,width:432,height:534)) }
            return Array(UnsafeBufferPointer(start:c.data!.assumingMemoryBound(to:UInt8.self),count:432*534*4))
        }
        let source = raster([base.cgImage()])
        let combined = raster([tail.texture!.cgImage(),bodyTexture(base).cgImage()])
        let maximumError = zip(source,combined).map { abs(Int($0)-Int($1)) }.max()!
        precondition(maximumError <= 2,"Neutral split must reconstruct the original without holes")
        print("Tail split check: maximum RGBA reconstruction error \(maximumError)/255")
        for (name,image) in [("body",bodyTexture(base).cgImage()),("tail-layer",tail.texture!.cgImage()),("mask",maskImage)] {
            let dest = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name+".png") as CFURL,UTType.png.identifier as CFString,1,nil)!
            CGImageDestinationAddImage(dest,image,nil); precondition(CGImageDestinationFinalize(dest))
        }
    }
    func update(time: Double, enabled: Bool, greetingElapsed: Double? = nil) {
        let dt = min(0.05,max(0,time - (lastTime ?? time)))
        lastTime = time
        let target = enabled && greetingElapsed == nil ? 1.0 : 0.0
        strength += (target-strength) * (1-exp(-dt/0.35))
        let entry = greetingElapsed.map { max(0,1-$0/0.30) } ?? 1
        let pose = TailPose.at(time,strength:strength*entry)
        let warp = SKWarpGeometryGrid(columns:columns,rows:rows,sourcePositions:points,destinationPositions:points.map(pose.point))
        tail.warpGeometry = warp; rootFill.warpGeometry = warp
        node.isHidden = greetingElapsed.map { $0 >= 0.30 } ?? false
    }
    func bodyTexture(_ texture: SKTexture) -> SKTexture {
        let id = ObjectIdentifier(texture)
        if let cached = bodyTextures[id] { return cached }
        let result = Self.masked(texture,mask:maskImage,keepTail:false)
        bodyTextures[id] = result
        return result
    }
    private static func masked(_ texture: SKTexture, mask: CGImage, keepTail: Bool) -> SKTexture {
        let c = CGContext(data:nil,width:432,height:534,bitsPerComponent:8,bytesPerRow:432*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x:0,y:0,width:432,height:534)
        c.draw(texture.cgImage(),in:rect)
        c.setBlendMode(keepTail ? .destinationIn : .destinationOut)
        c.draw(mask,in:rect)
        return SKTexture(cgImage:c.makeImage()!)
    }
    private static func makeMask(base: SKTexture) -> SKTexture {
        let context = CGContext(data:nil,width:432,height:534,bitsPerComponent:8,bytesPerRow:432*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Coordinates trace the visible tail/foreground boundary, not a rectangular body region.
        context.setShouldAntialias(false)
        context.translateBy(x:0,y:534); context.scaleBy(x:1,y:-1)
        let path = CGMutablePath()
        path.move(to:CGPoint(x:271,y:443))
        for p in [CGPoint(x:282,y:437),CGPoint(x:295,y:434),CGPoint(x:309,y:431),CGPoint(x:323,y:426),CGPoint(x:335,y:418),CGPoint(x:345,y:410),CGPoint(x:351,y:405),CGPoint(x:345,y:398),CGPoint(x:342,y:389),CGPoint(x:343,y:378),CGPoint(x:347,y:365),CGPoint(x:351,y:351),CGPoint(x:357,y:354),CGPoint(x:367,y:363),CGPoint(x:379,y:373),CGPoint(x:383,y:375),CGPoint(x:391,y:368),CGPoint(x:409,y:359),CGPoint(x:432,y:348),CGPoint(x:450,y:348),CGPoint(x:450,y:490),CGPoint(x:290,y:490),CGPoint(x:276,y:478),CGPoint(x:272,y:463)] { path.addLine(to:p) }
        path.closeSubpath(); context.addPath(path); context.setFillColor(CGColor(gray:1,alpha:1)); context.fillPath()
        let source = CGContext(data:nil,width:432,height:534,bitsPerComponent:8,bytesPerRow:432*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        source.draw(base.cgImage(),in:CGRect(x:0,y:0,width:432,height:534))
        let pixels = source.data!.assumingMemoryBound(to:UInt8.self)
        let maskPixels = context.data!.assumingMemoryBound(to:UInt8.self)
        // Cyan strands overlap the left fluke; they belong to the stationary hair layer.
        for y in 350..<415 { for x in 330..<359 {
            let i = (y*432+x)*4
            if Int(pixels[i+1]) > 100 && Double(pixels[i+1]) > Double(pixels[i])*1.7 {
                for channel in 0..<4 { maskPixels[i+channel] = 0 }
            }
        } }
        return SKTexture(cgImage:context.makeImage()!)
    }
}

func runTailChecks() {
    let anchor = SIMD2<Float>(266.0/432,90.0/534)
    var previous = TailPose.at(0,strength:1).point(SIMD2(0.94,0.29))
    for frame in 0...576 {
        let pose = TailPose.at(Double(frame)/60,strength:1)
        precondition(simd_distance(pose.point(anchor),anchor) < 0.000001,"Tail root must stay fixed")
        let tip = pose.point(SIMD2(0.94,0.29))
        precondition(simd_distance(tip,previous) < 0.002,"Tail tip must move continuously")
        previous = tip
    }
    let neutral = TailPose.at(2,strength:0)
    for p in [anchor,SIMD2<Float>(0.9,0.2),SIMD2<Float>(0.8,0.3)] { precondition(simd_distance(neutral.point(p),p)<0.000001) }
    print("Tail checks passed: anchored root, bounded continuous tip, neutral pose when disabled.")
}
