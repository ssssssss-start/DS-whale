import Foundation
import AVFoundation

private func frameData(_ value: [String:Any]) -> Data {
    var data = try! JSONSerialization.data(withJSONObject:value); data.append(10); return data
}

private final class FakePCMOutput: PCMOutput {
    var onStarted: (() -> Void)?
    var onFinished: (() -> Void)?
    var onLevel: ((Double) -> Void)?
    var onUnderrun: (() -> Void)?
    var onFailure: (() -> Void)?
    var bytes = 0
    var plays = 0
    var stopped = false
    var finished = false
    func append(_ data: Data) throws { assert(!stopped); bytes += data.count }
    func play() throws { plays += 1; onStarted?() }
    func finish() throws { finished = true; onFinished?() }
    func stop() { stopped = true }
}

private final class PCMProtocol: URLProtocol {
    static var requests = 0
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        let response = HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["X-Whale-Stream":"pcm-v1","Content-Type":"application/x-ndjson"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        let meta = frameData(["type":"meta","sample_rate":24000,"channels":1,"format":"pcm_s16le"])
        let audio = frameData(["type":"audio","seq":0,"pcm":Data(repeating:0,count:9600).base64EncodedString()])
        client?.urlProtocol(self,didLoad:meta)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.02) { [self] in
            guard !stopped else { return }
            client?.urlProtocol(self,didLoad:audio.prefix(19))
            client?.urlProtocol(self,didLoad:audio.dropFirst(19))
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.18) { [self] in
            guard !stopped else { return }
            client?.urlProtocol(self,didLoad:frameData(["type":"end","cached":false,"timings":["copy":10,"first_audio":20,"total":180]]))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { stopped = true }
}

func runVoiceStreamChecks() {
    let frames = PCMFrames(); var count = 0
    frames.audio = { count += $0.count }
    let meta = frameData(["type":"meta","sample_rate":24000,"channels":1,"format":"pcm_s16le"])
    let packet = frameData(["type":"audio","seq":0,"pcm":Data([0,0,1,0]).base64EncodedString()])
    try! frames.append(meta.prefix(7)); try! frames.append(meta.dropFirst(7)); try! frames.append(packet)
    assert(count == 4 && !frames.ended)
    do { try frames.finish(); assertionFailure("Missing end must fail") } catch {}
    do { try frames.append(packet); assertionFailure("Duplicate sequence must fail") } catch {}
    let multiple = PCMFrames(); var bytes = 0; multiple.audio = { bytes += $0.count }
    try! multiple.append(meta)
    var batch = Data()
    for index in 0..<40 { batch.append(frameData(["type":"audio","seq":index,"pcm":Data(repeating:0,count:9600).base64EncodedString()])) }
    try! multiple.append(batch); assert(bytes == 384000,"Large HTTP batches must remain frame-bounded")
    let suite = "whale-stream-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName:suite)!
    defer { defaults.removePersistentDomain(forName:suite) }
    let settings = ProactiveSettings(defaults:defaults)
    settings.proactive = true; settings.quietStart = 0; settings.quietEnd = 0
    let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [PCMProtocol.self]
    let session = URLSession(configuration:configuration)
    defer { session.invalidateAndCancel() }
    var outputs: [FakePCMOutput] = []
    let pipeline = VoicePipeline(settings:settings,session:session,credential:"mock",provider:.mira,streaming:true,recording:false,makePCMPlayer:{ let output = FakePCMOutput(); outputs.append(output); return output })
    func drain(_ duration:Double) { RunLoop.current.run(until:Date(timeIntervalSinceNow:duration)) }
    pipeline.receive(["type":"start","turn":"stream-direct","startedAt":Date().timeIntervalSince1970*1000])
    pipeline.receive(["type":"sentence","turn":"stream-direct","index":0,"text":"固定测试短句。"])
    pipeline.receive(["type":"end","turn":"stream-direct"])
    drain(0.08)
    assert(outputs.count == 1 && outputs[0].plays == 1 && outputs[0].bytes == 9600)
    assert(!outputs[0].finished,"Playback must start before the HTTP response ends")
    drain(0.2); assert(outputs[0].finished && !pipeline.isPlaying)
    pipeline.receive(["type":"proactive","event":["id":"cancel-stream","text":"固定测试。","kind":"decision","priority":1,"expiresAt":Date().timeIntervalSince1970*1000+60000]])
    drain(0.06); let played = outputs.last!
    settings.setDND(minutes:30); pipeline.settingsChanged(); drain(0.25)
    assert(played.stopped && !played.finished,"DND cancellation must reject the delayed end and stop PCM")
    assert(!pipeline.isPlaying)
    settings.setDND(minutes:0); pipeline.settingsChanged(); drain(0.02)
    assert(PCMProtocol.requests == 2,"No replay after DND")
    pipeline.cancel()
    print("PCM stream checks passed: split/large frames, sequence/truncation validation, playback before HTTP end, DND cancellation and no replay (mock audio sink).")
}

func runPCMAudioCheck() throws {
    let url = Bundle.main.url(forResource:"welcome",withExtension:"mp3",subdirectory:"sounds")!
    let file = try AVAudioFile(forReading:url)
    let source = AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length))!
    try file.read(into:source)
    let target = AVAudioFormat(standardFormatWithSampleRate:24000,channels:1)!
    let converter = AVAudioConverter(from:file.processingFormat,to:target)!
    let count = AVAudioFrameCount(Double(file.length)*24000/file.processingFormat.sampleRate)+256
    let output = AVAudioPCMBuffer(pcmFormat:target,frameCapacity:count)!
    var supplied = false; var conversionError: NSError?
    converter.convert(to:output,error:&conversionError) { _,status in
        if supplied { status.pointee = .endOfStream; return nil }
        supplied = true; status.pointee = .haveData; return source
    }
    if let conversionError { throw conversionError }
    var pcm = Data()
    for index in 0..<Int(output.frameLength) {
        var value = Int16(max(-32768,min(32767,Double(output.floatChannelData![0][index])*32767))).littleEndian
        withUnsafeBytes(of:&value) { pcm.append(contentsOf:$0) }
    }
    let playback = PCMPlayback(); var started = false; var finished = false
    playback.onStarted = { started = true }
    playback.onFinished = { finished = true }
    let bytes = pcm
    for offset in stride(from:0,to:bytes.count,by:9600) {
        let packet = bytes.subdata(in:offset..<min(offset+9600,bytes.count))
        DispatchQueue.main.asyncAfter(deadline:.now()+Double(offset/9600)*0.05) {
            do { try playback.append(packet); try playback.play(); if offset+9600 >= bytes.count { try playback.finish() } }
            catch { print("PCM hardware check failed"); playback.stop() }
        }
    }
    let deadline = Date(timeIntervalSinceNow:Double(output.frameLength)/24000+5)
    while !finished && Date() < deadline { RunLoop.current.run(until:Date(timeIntervalSinceNow:0.02)) }
    playback.stop()
    guard started && finished else { throw SpeechStreamError.unavailable }
    print("PCM hardware playback passed: bundled fixed welcome, incremental chunks, actual audio engine start and drain.")
}
