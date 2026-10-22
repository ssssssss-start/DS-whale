import AVFoundation

final class AudioFeedback {
    private var voicePlayer: AVAudioPlayer?
    private var cuePlayer: AVAudioPlayer?
    private var prepared: [String: AVAudioPlayer] = [:]
    var muted = UserDefaults.standard.bool(forKey: "muted") {
        didSet {
            UserDefaults.standard.set(muted, forKey: "muted")
            if muted { stop() }
        }
    }
    func player(for behavior: Behavior) -> AVAudioPlayer? {
        guard let key = behavior.voice else { return nil }
        if let existing = prepared[key] { return existing }
        guard let url = Bundle.main.url(forResource: key, withExtension: "mp3", subdirectory: "sounds"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        prepared[key] = player
        return player
    }
    func duration(for behavior: Behavior) -> TimeInterval { muted ? 0 : (player(for: behavior)?.duration ?? 0) }
    func play(_ behavior: Behavior) {
        stop()
        guard !muted else { return }
        if behavior == .poke { playCue() }
        voicePlayer = player(for: behavior)
        voicePlayer?.currentTime = 0
        voicePlayer?.volume = 0.78
        voicePlayer?.play()
    }
    func stop() {
        voicePlayer?.stop()
        cuePlayer?.stop()
    }
    private func playCue() {
        let sampleRate = 22050
        let count = Int(Double(sampleRate) * 0.085)
        var wave = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { wave.append(contentsOf: $0) }
        }
        append(UInt32(36 + count * 2))
        wave.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
        append(UInt16(2)); append(UInt16(16))
        wave.append(Data("data".utf8)); append(UInt32(count * 2))
        for index in 0..<count {
            let t = Double(index) / Double(sampleRate)
            let fade = pow(1 - Double(index) / Double(count), 2) * min(1, t / 0.008)
            append(Int16(sin(2 * .pi * 720 * t) * fade * 3200))
        }
        cuePlayer = try? AVAudioPlayer(data: wave)
        cuePlayer?.volume = 0.25
        cuePlayer?.play()
    }
}
