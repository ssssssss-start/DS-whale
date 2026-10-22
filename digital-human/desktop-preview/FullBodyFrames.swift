import AppKit
import SpriteKit
import ImageIO

struct FullBodyFrames {
    let images: [CGImage]
    var textures: [SKTexture] { images.map { SKTexture(cgImage: $0) } }

    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var cutouts: [CGImage] = []
        var bounds = CGRect.null
        let width = sheet.width / 5
        let height = sheet.height
        for frame in 0..<5 {
            let x = Int((Double(frame) * Double(sheet.width) / 5).rounded())
            guard let crop = sheet.cropping(to: CGRect(x: x, y: 0, width: width, height: height)) else { return nil }
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let result: CGImage? = pixels.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
                let bytes = buffer.bindMemory(to: UInt8.self)
                var background = [Bool](repeating: false, count: width * height)
                var queue: [Int] = []
                func enqueue(_ p: Int) {
                    guard !background[p] else { return }
                    let i = p * 4
                    // Only edge-connected black is removed; enclosed dark costume details survive.
                    guard max(bytes[i], bytes[i + 1], bytes[i + 2]) < 28 else { return }
                    background[p] = true
                    queue.append(p)
                }
                for x in 0..<width { enqueue(x); enqueue((height - 1) * width + x) }
                for y in 0..<height { enqueue(y * width); enqueue(y * width + width - 1) }
                // The source also has enclosed black backdrop inside the hair curl
                // and beside the tail. Protect the central face/costume ink.
                for y in 0..<height {
                    for x in 0..<width {
                        let centralInk = x > width / 4 && x < width * 7 / 10
                            && y > height / 3 && y < height * 94 / 100
                        let p = y * width + x, i = p * 4
                        if !centralInk && max(bytes[i], bytes[i + 1], bytes[i + 2]) < 8 { enqueue(p) }
                    }
                }
                var cursor = 0
                while cursor < queue.count {
                    let p = queue[cursor]
                    cursor += 1
                    let x = p % width, y = p / width
                    if x > 0 { enqueue(p - 1) }
                    if x + 1 < width { enqueue(p + 1) }
                    if y > 0 { enqueue(p - width) }
                    if y + 1 < height { enqueue(p + width) }
                }
                for p in queue {
                    for channel in 0..<4 { bytes[p * 4 + channel] = 0 }
                }
                for y in 1..<(height - 1) {
                    for x in 1..<(width - 1) {
                        let p = y * width + x, i = p * 4
                        if !background[p] && (background[p - 1] || background[p + 1]
                            || background[p - width] || background[p + width]) {
                            let brightness = Int(max(bytes[i], bytes[i + 1], bytes[i + 2]))
                            if brightness < 80 { bytes[i + 3] = UInt8(brightness * 255 / 80) }
                        }
                    }
                }
                var left = width, right = 0, top = height, bottom = 0
                for p in 0..<(width * height) where !background[p] {
                    left = min(left, p % width); right = max(right, p % width)
                    top = min(top, p / width); bottom = max(bottom, p / width)
                }
                bounds = bounds.union(CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1))
                return context.makeImage()
            }
            guard let result else { return nil }
            cutouts.append(result)
        }
        // A shared crop preserves the original registration and feet position across all five drawings.
        let cropBounds = bounds.insetBy(dx: -2, dy: -2).intersection(CGRect(x: 0, y: 0, width: width, height: height))
        images = cutouts.compactMap { $0.cropping(to: cropBounds) }
        guard images.count == 5 else { return nil }
    }
}
