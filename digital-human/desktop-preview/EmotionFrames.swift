import SpriteKit

final class EmotionFrames {
    private var frames: [Behavior: [SKTexture]] = [:]
    init() {
        for behavior in Behavior.emotions {
            var sequence: [SKTexture] = []
            for step in 0...32 {
                let name = String(format:"%@-%02d",behavior.rawValue,step)
                guard let url = Bundle.main.url(forResource:name,withExtension:"png",subdirectory:"emotions-v1"),
                      let image = NSImage(contentsOf:url) else { break }
                let texture = SKTexture(image:image); texture.filteringMode = .linear; sequence.append(texture)
            }
            if sequence.count == 33 { frames[behavior] = sequence }
        }
        SKTexture.preload(frames.values.flatMap { $0 }) {}
    }
    func texture(_ behavior: Behavior, level: Double) -> SKTexture? {
        guard let sequence = frames[behavior] else { return nil }
        return sequence[max(0,min(32,Int((max(0,min(1,level))*32).rounded())))]
    }
    func validate() {
        precondition(frames.count == 4, "All four emotion sequences must be bundled")
        for sequence in frames.values { precondition(sequence.count == 33 && sequence.allSatisfy { $0.size() == CGSize(width:432,height:534) }) }
    }
}
