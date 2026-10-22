import AppKit
import SpriteKit

final class WaveMotion {
    private var transitions: [String: [SKTexture]] = [:]
    private var faceLift: [SKTexture] = []

    init(size: CGSize) {
        for (a, b) in [(0,1), (1,2), (2,3), (3,4), (4,1)] {
            var textures: [SKTexture] = []
            for step in 0...32 {
                let name = String(format: "%d-%d-%02d", a, b, step)
                guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "wave-tweens"),
                      let image = NSImage(contentsOf: url) else { break }
                let texture = SKTexture(cgImage:cleanHairEdges(image.cgImage(forProposedRect:nil,context:nil,hints:nil)!))
                texture.filteringMode = .linear
                textures.append(texture)
            }
            if textures.count == 33 { transitions["\(a)-\(b)"] = textures }
        }
        faceLift = transitions["0-1"] ?? []
        var lift: [SKTexture] = []
        for step in 0...96 {
            let name = String(format:"lift-%03d",step)
            guard let url = Bundle.main.url(forResource:name,withExtension:"png",subdirectory:"lift-v3"),
                  let image = NSImage(contentsOf:url) else { break }
            let texture = SKTexture(cgImage:cleanHairEdges(image.cgImage(forProposedRect:nil,context:nil,hints:nil)!)); texture.filteringMode = .linear
            lift.append(texture)
        }
        if lift.count == 97 { transitions["0-1"] = lift }
        SKTexture.preload(Array(transitions.values).flatMap { $0 } + faceLift) {}
    }

    func texture(for pose: WavePose, frames: [SKTexture]) -> SKTexture {
        if let textures = transitions["\(pose.from)-\(pose.to)"] {
            let step = max(0,min(textures.count-1,Int((pose.blend * Double(textures.count-1)).rounded())))
            return textures[step]
        } else if let textures = transitions["\(pose.to)-\(pose.from)"] {
            let step = max(0,min(textures.count-1,Int((pose.blend * Double(textures.count-1)).rounded())))
            return textures[textures.count - 1 - step]
        } else {
            return frames[pose.blend < 0.5 ? pose.from : pose.to]
        }
    }
    func faceTexture(for closure: Double, frames: [SKTexture]) -> SKTexture {
        // Eye/face transitions must not inherit the newly generated arm-lift poses.
        let progress = max(0,min(1,closure))
        if progress < 0.15, !faceLift.isEmpty {
            return faceLift[min(32,Int((progress / 0.15 * 32).rounded()))]
        }
        guard let textures = transitions["1-2"] else { return frames[progress < 0.5 ? 0 : 2] }
        let step = max(0,min(32,Int(((progress - 0.15) / 0.85 * 32).rounded())))
        return textures[step]
    }
    func apply(_ pose: WavePose, frames: [SKTexture], to sprite: SKSpriteNode) {
        sprite.shader = nil
        sprite.texture = texture(for:pose,frames:frames)
    }
}
