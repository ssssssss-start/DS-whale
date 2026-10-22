import CoreGraphics

// Render-time black-matte cleanup, limited to the exposed left hair curls.
// Face, outfit, hands and registered frame placement remain unchanged.
func cleanHairEdges(_ image: CGImage) -> CGImage {
    let w = image.width, h = image.height
    let c = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
        space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
    let p = c.data!.assumingMemoryBound(to:UInt8.self)
    let original = Array(UnsafeBufferPointer(start:p,count:w*h*4))
    func region(_ x:Int,_ y:Int) -> Bool {
        let u = Double(x)/Double(w), v = Double(y)/Double(h)
        return v > 0.54 && v < 0.89 && u < (v > 0.79 ? 0.30 : 0.22)
    }
    // Black remnants inside curls are background too, even when enclosed by hair.
    var clear = [Bool](repeating:false,count:w*h)
    var queue: [Int] = []
    let yStart = max(1,Int(Double(h)*0.54)), yEnd = min(h-1,Int(Double(h)*0.89)+1)
    let xEnd = min(w-1,Int(Double(w)*0.30)+1)
    for y in yStart..<yEnd { for x in 0..<xEnd where region(x,y) {
        let n = y*w+x, i=n*4
        if original[i+3] == 0 || max(original[i],original[i+1],original[i+2]) < 12 {
            clear[n]=true; queue.append(n)
        }
    } }
    var cursor=0
    while cursor<queue.count {
        let n=queue[cursor]; cursor+=1
        for (x,y) in [(n%w-1,n/w),(n%w+1,n/w),(n%w,n/w-1),(n%w,n/w+1)] {
            guard x>=0,x<w,y>=0,y<h,region(x,y) else { continue }
            let q=y*w+x,i=q*4
            if !clear[q] && max(original[i],original[i+1],original[i+2]) < 38 {
                clear[q]=true; queue.append(q)
            }
        }
    }
    for y in yStart..<yEnd { for x in 1..<xEnd where region(x,y) {
        let n=y*w+x,i=n*4
        if clear[n] { for k in 0..<4 { p[i+k]=0 }; continue }
        guard clear[n-1] || clear[n+1] || clear[n-w] || clear[n+w] else { continue }
        let brightness=Double(max(original[i],original[i+1],original[i+2]))
        let coverage=min(1,max(0,(brightness-38)/32))
        // Keep premultiplied RGB and alpha consistent; no opaque cyan fringe.
        for k in 0..<4 { p[i+k]=UInt8((Double(original[i+k])*coverage).rounded()) }
    } }
    let cleaned = Array(UnsafeBufferPointer(start:p,count:w*h*4))
    for y in yStart..<yEnd { for x in 1..<xEnd where region(x,y) {
        let n=y*w+x,i=n*4
        let neighbors=[n-1,n+1,n-w,n+w]
        guard neighbors.contains(where:{cleaned[$0*4+3]==0}),
              cleaned[i+3]>0 else { continue }
        // A subpixel coverage filter softens only the silhouette, never interior strand detail.
        for k in 0..<4 {
            let value=Double(cleaned[i+k])*0.75 + neighbors.reduce(0.0) { $0 + Double(cleaned[$1*4+k])*0.0625 }
            p[i+k]=UInt8(value.rounded())
        }
    } }
    return c.makeImage()!
}

func runHairEdgeChecks() {
    let w=100,h=100
    let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
        space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    let p=c.data!.assumingMemoryBound(to:UInt8.self)
    func pixel(_ x:Int,_ y:Int,_ rgba:[UInt8]) { for k in 0..<4 { p[(y*w+x)*4+k]=rgba[k] } }
    pixel(10,65,[8,8,8,255]); pixel(11,65,[16,22,30,255])
    pixel(12,65,[15,38,55,255]); pixel(13,65,[20,110,220,255])
    pixel(50,65,[8,8,8,255]); pixel(10,20,[8,8,8,255])
    let input=c.makeImage()!
    let output=cleanHairEdges(input)
    let result=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
        space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    result.draw(output,in:CGRect(x:0,y:0,width:w,height:h))
    let q=result.data!.assumingMemoryBound(to:UInt8.self)
    precondition(q[(65*w+10)*4+3]==0 && q[(65*w+11)*4+3]==0)
    precondition(q[(65*w+12)*4+3]>0 && q[(65*w+12)*4+3]<255)
    precondition(q[(65*w+13)*4+2] > 150 && q[(65*w+13)*4+3] > 180)
    for (x,y) in [(50,65),(10,20)] { for k in 0..<4 { precondition(q[(y*w+x)*4+k]==p[(y*w+x)*4+k]) } }
    print("Hair edge checks passed: matte removal, soft alpha, preserved blue strands and protected face/outfit.")
}
