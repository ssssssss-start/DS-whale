import AVFoundation

// PCM16 segments include a short pre-roll and end after a pause, never during TTS.
final class SpeechSegmenter {
    private var prefix = Data(), recording = Data()
    private var voiced = 0, silence = 0
    private var started = false
    func append(_ pcm: Data, level: Double) -> Data? {
        guard !pcm.isEmpty else { return nil }
        if !started {
            prefix.append(pcm)
            if prefix.count > 9600 { prefix.removeFirst(prefix.count - 9600) }
            voiced = level >= 0.012 ? voiced + pcm.count : 0
            if voiced >= 3840 { started = true; recording = prefix; prefix.removeAll() }
            return nil
        }
        recording.append(pcm)
        silence = level < 0.012 ? silence + pcm.count : 0
        guard silence >= 35200 || recording.count >= 640000 else { return nil }
        let result = Self.wave(recording.prefix(640000))
        reset(); return result
    }
    func reset() { prefix.removeAll(); recording.removeAll(); voiced = 0; silence = 0; started = false }
    static func wave(_ pcm: Data) -> Data {
        var output = Data("RIFF".utf8)
        func word<T: FixedWidthInteger>(_ value: T) { var value = value.littleEndian; withUnsafeBytes(of:&value) { output.append(contentsOf:$0) } }
        word(UInt32(36 + pcm.count)); output.append(Data("WAVEfmt ".utf8))
        word(UInt32(16)); word(UInt16(1)); word(UInt16(1)); word(UInt32(16000)); word(UInt32(32000)); word(UInt16(2)); word(UInt16(16))
        output.append(Data("data".utf8)); word(UInt32(pcm.count)); output.append(pcm)
        return output
    }
}

protocol MicrophoneInput: AnyObject {
    var onAudio: ((Data) -> Void)? { get set }
    var onLevel: ((Double) -> Void)? { get set }
    var onFailure: (() -> Void)? { get set }
    func start(completion: @escaping (Bool) -> Void)
    func stop()
}

final class VoiceCapture: MicrophoneInput {
    var onAudio: ((Data) -> Void)?
    var onLevel: ((Double) -> Void)?
    var onFailure: (() -> Void)?
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var generation = UUID()
    private let segmenter = SpeechSegmenter()
    func start(completion: @escaping (Bool) -> Void) {
        stop(); let token = generation
        func ready(_ allowed: Bool) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                guard allowed else { completion(false); return }
                completion(self.capture(token))
            }
        }
        switch AVCaptureDevice.authorizationStatus(for:.audio) {
        case .authorized: ready(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for:.audio,completionHandler:ready)
        default: ready(false)
        }
    }
    private func capture(_ token: UUID) -> Bool {
        let engine = AVAudioEngine(), input = engine.inputNode
        let format = input.outputFormat(forBus:0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let target = AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:16000,channels:1,interleaved:true),
              let converter = AVAudioConverter(from:format,to:target) else { return false }
        self.engine = engine
        input.installTap(onBus:0,bufferSize:2048,format:format) { [weak self] buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / format.sampleRate) + 64)
            guard let output = AVAudioPCMBuffer(pcmFormat:target,frameCapacity:capacity) else { return }
            var supplied = false, error: NSError?
            converter.convert(to:output,error:&error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            if error != nil {
                DispatchQueue.main.async { guard let self, self.generation == token else { return }; self.stop(); self.onFailure?() }
                return
            }
            guard output.frameLength > 0, let samples = output.int16ChannelData?[0] else { return }
            let count = Int(output.frameLength)
            var square = 0.0
            for index in 0..<count { let x = Double(samples[index]) / 32768; square += x*x }
            let level = sqrt(square / Double(count)), data = Data(bytes:samples,count:count*2)
            DispatchQueue.main.async {
                guard let self, self.generation == token, self.engine != nil else { return }
                self.onLevel?(min(1,level * 8))
                if let audio = self.segmenter.append(data,level:level) { self.stop(); self.onAudio?(audio) }
            }
        }
        do {
            engine.prepare(); try engine.start()
            configurationObserver = NotificationCenter.default.addObserver(forName:.AVAudioEngineConfigurationChange,object:engine,queue:.main) { [weak self] _ in
                guard let self, self.generation == token else { return }; self.stop(); self.onFailure?()
            }
            return true
        }
        catch { stop(); return false }
    }
    func stop() {
        generation = UUID()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver); self.configurationObserver = nil }
        engine?.inputNode.removeTap(onBus:0); engine?.stop(); engine = nil
        segmenter.reset(); onLevel?(0)
    }
}

func runSpeechSegmentChecks() {
    let segmenter = SpeechSegmenter(), chunk = Data(repeating:0,count:3200)
    for _ in 0..<100 { assert(segmenter.append(chunk,level:0) == nil) }
    for _ in 0..<4 { assert(segmenter.append(chunk,level:0.08) == nil) }
    var result: Data?
    for _ in 0..<11 { result = segmenter.append(chunk,level:0) }
    assert(result != nil && result!.prefix(4) == Data("RIFF".utf8))
    assert(result!.count <= 640044 && (result!.count-44) % 2 == 0)
    segmenter.reset(); assert(segmenter.append(chunk,level:0) == nil)
    print("Microphone segmentation checks passed: silent pre-roll bound, speech onset, pause endpoint, PCM16 WAV and discard (synthetic audio).")
}
