import AVFoundation

protocol PCMOutput: AnyObject {
    var onStarted: (() -> Void)? { get set }
    var onFinished: (() -> Void)? { get set }
    var onLevel: ((Double) -> Void)? { get set }
    var onUnderrun: (() -> Void)? { get set }
    var onFailure: (() -> Void)? { get set }
    func append(_ data: Data) throws
    func play() throws
    func finish() throws
    func stop()
}

final class PCMPlayback: PCMOutput {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate:24000,channels:1)!
    private var requested = false
    private var started = false
    private var starting = false
    private var ended = false
    private var stopped = false
    private var queued = 0
    private var tap = false
    var onStarted: (() -> Void)?
    var onFinished: (() -> Void)?
    var onLevel: ((Double) -> Void)?
    var onUnderrun: (() -> Void)?
    var onFailure: (() -> Void)?
    init() {
        engine.attach(player); engine.connect(player,to:engine.mainMixerNode,format:format)
        player.volume = 0.78
    }
    func append(_ data: Data) throws {
        guard !stopped, !ended, !data.isEmpty, data.count % 2 == 0 else { throw SpeechStreamError.invalidFrame }
        let count = data.count / 2
        guard queued + count <= 24000 * 120,
              let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(count)) else { throw SpeechStreamError.invalidFrame }
        buffer.frameLength = AVAudioFrameCount(count)
        let channel = buffer.floatChannelData![0]
        data.withUnsafeBytes { bytes in
            let raw = bytes.bindMemory(to:UInt8.self)
            for index in 0..<count {
                let sample = Int16(bitPattern:UInt16(raw[index*2]) | UInt16(raw[index*2+1]) << 8)
                channel[index] = Float(sample) / 32768
            }
        }
        queued += count
        player.scheduleBuffer(buffer,completionCallbackType:.dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.stopped else { return }
                self.queued -= count
                if self.queued == 0 {
                    if self.ended { self.complete() }
                    else { self.onUnderrun?() }
                }
            }
        }
        try startIfReady()
    }
    func play() throws { requested = true; try startIfReady() }
    private func startIfReady() throws {
        guard requested, !started, !starting, !stopped, queued >= 3600 || (ended && queued > 0) else { return }
        engine.mainMixerNode.installTap(onBus:0,bufferSize:512,format:nil) { [weak self] buffer,_ in
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var square = 0.0
            for index in 0..<Int(buffer.frameLength) { square += Double(samples[index] * samples[index]) }
            let rms = sqrt(square / Double(buffer.frameLength))
            let level = min(1,max(0,(20 * log10(max(0.00001,rms)) + 48) / 40))
            DispatchQueue.main.async { [weak self] in if self?.stopped == false { self?.onLevel?(level) } }
        }
        tap = true; engine.prepare(); try engine.start(); starting = true; waitForIO()
    }
    private func waitForIO(_ attempt: Int = 0) {
        guard !stopped else { return }
        // Core Audio can return from start() before the node's first IO cycle.
        if engine.isRunning, let time = player.lastRenderTime, time.isSampleTimeValid {
            player.play(); starting = false; started = true; onStarted?(); return
        }
        if attempt >= 100 { stop(); onFailure?(); return }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.01) { [weak self] in self?.waitForIO(attempt+1) }
    }
    func finish() throws {
        ended = true
        try startIfReady()
        if queued == 0 { complete() }
    }
    private func complete() { guard !stopped else { return }; stop(); onFinished?() }
    func stop() {
        guard !stopped else { return }
        stopped = true; player.stop(); engine.stop()
        if tap { engine.mainMixerNode.removeTap(onBus:0); tap = false }
    }
}
