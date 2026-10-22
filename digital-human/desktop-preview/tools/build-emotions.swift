import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision
import Darwin
setbuf(stdout,nil)

let root = URL(fileURLWithPath:CommandLine.arguments[1])
let width = 432, height = 534
func load(_ url: URL) -> CGImage {
    let source = CGImageSourceCreateWithURL(url as CFURL,nil)!
    return CGImageSourceCreateImageAtIndex(source,0,nil)!
}
func bitmap(_ pixels: [UInt8]) -> CGImage {
    CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,
        space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
        provider:CGDataProvider(data:Data(pixels) as CFData)!,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
}
func pixels(_ image: CGImage) -> [UInt8] {
    var result = [UInt8](repeating:0,count:width*height*4)
    result.withUnsafeMutableBytes { raw in
        let c = CGContext(data:raw.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.interpolationQuality = .high; c.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
    }
    return result
}
func save(_ image: CGImage, _ name: String) {
    let target = CGImageDestinationCreateWithURL(root.appendingPathComponent(name) as CFURL,UTType.png.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(target,image,nil); precondition(CGImageDestinationFinalize(target))
}
func mask(_ x: Int, _ y: Int) -> Float {
    let d = hypot((Double(x)-205)/108,(Double(y)-216)/66)
    let t = min(1,max(0,(d-0.84)/0.16))
    return Float(1-t*t*(3-2*t))
}
let base = pixels(load(root.appendingPathComponent("neutral.png")))
func composite(_ face: [UInt8]) -> [UInt8] {
    var result = base
    for y in 0..<height { for x in 0..<width {
        let weight = mask(x,y), i = (y*width+x)*4
        for c in 0..<3 { result[i+c] = UInt8((Float(base[i+c])*(1-weight)+Float(face[i+c])*weight).rounded()) }
        result[i+3] = base[i+3]
    } }
    return result
}
func flow(_ from: CGImage, _ to: CGImage) throws -> [Float] {
    try autoreleasepool {
        let request = VNGenerateOpticalFlowRequest(targetedCGImage:to,options:[:])
        request.revision = VNGenerateOpticalFlowRequestRevision1
        request.computationAccuracy = .veryHigh
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float
        try VNImageRequestHandler(cgImage:from,options:[:]).perform([request])
        let buffer = request.results!.first!.pixelBuffer
        CVPixelBufferLockBaseAddress(buffer,.readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer,.readOnly) }
        precondition(CVPixelBufferGetWidth(buffer) == width && CVPixelBufferGetHeight(buffer) == height)
        let pointer = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to:Float.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)/4
        var result = [Float](repeating:0,count:width*height*2)
        for y in 0..<height { for x in 0..<width*2 { result[y*width*2+x] = pointer[y*stride+x] } }
        return result
    }
}
func interpolate(_ a: [Float], _ b: [Float], _ ab: [Float], _ ba: [Float], _ t: Float) -> CGImage {
    func sample(_ values: [Float], _ x: Float, _ y: Float, _ channels: Int, _ channel: Int) -> Float {
        let xx = min(Float(width-1),max(0,x)), yy = min(Float(height-1),max(0,y))
        let ix = Int(xx), iy = Int(yy), nx = min(width-1,ix+1), ny = min(height-1,iy+1)
        let u = xx-Float(ix), v = yy-Float(iy)
        return values[(iy*width+ix)*channels+channel]*(1-u)*(1-v)
            + values[(iy*width+nx)*channels+channel]*u*(1-v)
            + values[(ny*width+ix)*channels+channel]*(1-u)*v
            + values[(ny*width+nx)*channels+channel]*u*v
    }
    let ap = a.map { UInt8(max(0,min(255,$0))) }, bp = b.map { UInt8(max(0,min(255,$0))) }
    let regions = [(133,188,185,232),(226,278,185,232),(187,227,232,260)]
    let guides = regions.enumerated().map { (index,region) in
        (feature(ap,region:region,mouth:index==2),feature(bp,region:region,mouth:index==2),region)
    }
    var result = [UInt8](repeating:0,count:width*height*4)
    // Inverse sampling fills every destination pixel; forward splatting left eyelid holes.
    for y in 0..<height { for x in 0..<width {
        let px = Float(x), py = Float(y)
        var ax = px, ay = py, bx = px, by = py
        for _ in 0..<5 {
            let adx = sample(ab,ax,ay,2,0), ady = sample(ab,ax,ay,2,1)
            let bdx = sample(ba,bx,by,2,0), bdy = sample(ba,bx,by,2,1)
            ax = px-t*adx; ay = py-t*ady
            bx = px-(1-t)*bdx; by = py-(1-t)*bdy
        }
        // Solve feature scaling analytically: a closing mouth has a large inverse
        // gradient, where fixed-point flow inversion cannot converge.
        for (index,guide) in guides.enumerated() {
            if index != 2 { continue }
            let (aa,bb,region) = guide
            let zone = index == 2 ? Feature(left:183,top:228,right:231,bottom:265)
                : Feature(left:Double(region.0)-5,top:178,right:Double(region.1)+5,bottom:242)
            let edge = min(min(Double(x)-zone.left,zone.right-Double(x)),min(Double(y)-zone.top,zone.bottom-Double(y)))
            if edge <= 0 { continue }
            let q = Float(min(1,edge/6)), w = q*q*(3-2*q)
            func inverse(_ from: Feature, _ to: Feature, _ amount: Float) -> (Float,Float) {
                let sx = Float(to.w/from.w), sy = Float(to.h/from.h)
                let dx = Float(to.cx)-sx*Float(from.cx), dy = Float(to.cy)-sy*Float(from.cy)
                let xx = (px-amount*dx)/(1+amount*(sx-1)), yy = (py-amount*dy)/(1+amount*(sy-1))
                return (min(Float(from.right+3),max(Float(from.left-3),xx)),min(Float(from.bottom+3),max(Float(from.top-3),yy)))
            }
            let av = inverse(aa,bb,t), bv = inverse(bb,aa,1-t)
            ax = ax*(1-w)+av.0*w; ay = ay*(1-w)+av.1*w
            bx = bx*(1-w)+bv.0*w; by = by*(1-w)+bv.1*w
        }
        for c in 0..<4 {
            let value = sample(a,ax,ay,4,c)*(1-t)+sample(b,bx,by,4,c)*t
            result[(y*width+x)*4+c] = UInt8(min(255,max(0,value.rounded())))
        }
    } }
    return bitmap(result)
}

struct Feature {
    let left: Double, top: Double, right: Double, bottom: Double
    var cx: Double { (left+right)/2 }; var cy: Double { (top+bottom)/2 }
    var w: Double { max(1,right-left) }; var h: Double { max(1,bottom-top) }
}
func feature(_ p: [UInt8], region: (Int,Int,Int,Int), mouth: Bool = false) -> Feature {
    var xs: [Int] = [], ys: [Int] = []
    for y in region.2..<region.3 { for x in region.0..<region.1 {
        let i = (y*width+x)*4, r = Double(p[i]), g = Double(p[i+1]), b = Double(p[i+2])
        let selected = mouth ? r > 130 && g < r*0.78 && b < r*0.88 : r < 120 && g < 70 && b < 100 && r > g*1.2 && r > b*0.9
        if selected { xs.append(x); ys.append(y) }
    } }
    precondition(xs.count > 8,"Facial feature must be visible: region \(region), mouth \(mouth), pixels \(xs.count)")
    let ordered = ys.sorted()
    return Feature(left:Double(xs.min()!),top:Double(ordered[Int(Double(ordered.count)*0.04)]),right:Double(xs.max()!),bottom:Double(ordered[Int(Double(ordered.count-1)*0.98)]))
}
func guidedFeatures(_ input: [Float], from a: [UInt8], to b: [UInt8]) -> [Float] {
    var output = input
    let regions = [(133,188,185,232),(226,278,185,232),(187,227,232,260)]
    for (index,region) in regions.enumerated() {
        if index != 2 { continue }
        let aa = feature(a,region:region,mouth:index==2), bb = feature(b,region:region,mouth:index==2)
        if CommandLine.arguments.contains("--landmarks") { print("feature \(index): \(aa) -> \(bb)") }
        let pad = index == 2 ? 10.0 : 9.0
        let zone = index == 2 ? aa : Feature(left:Double(region.0),top:183,right:Double(region.1),bottom:237)
        for y in Int(zone.top-pad)..<Int(zone.bottom+pad) { for x in Int(zone.left-pad)..<Int(zone.right+pad) {
            let xx = Double(x), yy = Double(y)
            let dx = bb.cx+(xx-aa.cx)*bb.w/aa.w-xx
            let dy = bb.cy+(yy-aa.cy)*bb.h/aa.h-yy
            let outside = max(max(zone.left-xx,xx-zone.right),max(zone.top-yy,yy-zone.bottom))
            let t = max(0,min(1,1-max(0,outside)/pad)), w = Float(t*t*(3-2*t))
            let i = (y*width+x)*2
            output[i] = input[i]*(1-w)+Float(dx)*w
            output[i+1] = input[i+1]*(1-w)+Float(dy)*w
        } }
    }
    return output
}

func sleepyLids(_ input: [UInt8], target: [UInt8], progress: Float) -> [UInt8] {
    var result = input
    func sample(_ p: [UInt8], _ x: Int, _ y: Float, _ c: Int) -> Float {
        let yy = max(0,min(Float(height-1),y)), a = Int(yy), b = min(height-1,a+1), u = yy-Float(a)
        return Float(p[(a*width+x)*4+c])*(1-u)+Float(p[(b*width+x)*4+c])*u
    }
    func contour(_ p: [UInt8], _ left: Int, _ right: Int) -> [Float] {
        var line = [Float](repeating:-1,count:right-left+1)
        for x in left...right {
            for y in 185..<232 {
                let i = (y*width+x)*4, r = Float(p[i]), g = Float(p[i+1]), b = Float(p[i+2])
                if r < 120 && g < 70 && b < 100 && r > g*1.2 && r > b*0.9 { line[x-left] = Float(y); break }
            }
        }
        for i in line.indices where line[i] < 0 {
            let lo = stride(from:i-1,through:0,by:-1).first { line[$0] >= 0 }
            let hi = ((i+1)..<line.count).first { line[$0] >= 0 }
            if let lo, let hi { line[i] = line[lo]+(line[hi]-line[lo])*Float(i-lo)/Float(hi-lo) }
            else { line[i] = lo.map { line[$0] } ?? hi.map { line[$0] } ?? 207 }
        }
        return line
    }
    for (left,right) in [(132,189),(225,279)] {
        let a = contour(base,left,right), b = contour(target,left,right)
        for x in left...right {
            let top = a[x-left]*(1-progress)+b[x-left]*progress
            let q = min(1,Float(min(x-left,right-x))/4), weight = q*q*(3-2*q)
            for y in 185..<238 {
                let i = (y*width+x)*4, yy = Float(y)
                for c in 0..<3 {
                    let value: Float
                    if yy < top-2 { value = Float(target[i+c]) }
                    else {
                        let position = (yy-top)/max(1,234-top)
                        let ay = a[x-left]+position*(234-a[x-left])
                        let by = b[x-left]+position*(234-b[x-left])
                        value = sample(base,x,ay,c)*(1-progress)+sample(target,x,by,c)*progress
                    }
                    result[i+c] = UInt8(max(0,min(255,(Float(input[i+c])*(1-weight)+value*weight).rounded())))
                }
            }
        }
    }
    return result
}

var metrics: [[String:Any]] = []
for name in ["shy","surprised","sad","sleepy"] {
    let raw = pixels(load(root.appendingPathComponent(name+"-source.png")))
    // Register against hair above/around the face, excluding eyes, eyebrows and mouth.
    var best = Double.infinity, ox = 0, oy = 0
    for dy in -8...8 { for dx in -8...8 {
        var error = 0.0, count = 0
        for y in stride(from:85,to:263,by:3) { for x in stride(from:90,to:320,by:3) {
            if x > 122 && x < 285 && y > 164 { continue }
            let i = (y*width+x)*4, j = ((y+dy)*width+x+dx)*4
            if base[i+3] < 250 || Int(base[i+2]) < Int(base[i])+25 { continue }
            for c in 0..<3 { error += pow(Double(Int(base[i+c])-Int(raw[j+c])),2) }; count += 1
        } }
        let score = error / Double(max(1,count))
        if score < best { best = score; ox = dx; oy = dy }
    } }
    var aligned = base
    for y in 10..<(height-10) { for x in 10..<(width-10) {
        let i = (y*width+x)*4, j = ((y+oy)*width+x+ox)*4
        for c in 0..<4 { aligned[i+c] = raw[j+c] }
    } }
    let end = composite(aligned)
    if CommandLine.arguments.contains("--landmarks") {
        _ = guidedFeatures([Float](repeating:0,count:width*height*2),from:base,to:end)
        continue
    }
    let ab = guidedFeatures(try flow(bitmap(base),bitmap(end)),from:base,to:end)
    let ba = guidedFeatures(try flow(bitmap(end),bitmap(base)),from:end,to:base)
    for step in 0...32 {
        var blended = step == 0 ? base : step == 32 ? end : composite(pixels(interpolate(base.map(Float.init),end.map(Float.init),ab,ba,Float(step)/32)))
        if name == "sleepy", step > 0, step < 32 { blended = composite(sleepyLids(blended,target:end,progress:Float(step)/32)) }
        // Outside the feathered face region every pixel, including alpha, stays identical.
        for y in 0..<height { for x in 0..<width where mask(x,y) == 0 {
            let i = (y*width+x)*4
            precondition(Array(blended[i..<i+4]) == Array(base[i..<i+4]))
        } }
        save(bitmap(blended),String(format:"%@-%02d.png",name,step))
    }
    metrics.append(["emotion":name,"dx":ox,"dy":oy,"hair_error":best,"frames":33,"body_pixels_unchanged":true])
    print("Built emotion \(name): 33 registered frames")
}
let report = try JSONSerialization.data(withJSONObject:metrics,options:[.prettyPrinted,.sortedKeys])
try report.write(to:root.appendingPathComponent("registration.json"))
