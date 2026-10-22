import Foundation

private func serverFrame(_ event: Int, id: String = "connection", audio: Data? = nil, body: [String:Any] = [:]) -> Data {
    var data = Data([0x11,audio == nil ? 0x94 : 0xb4,audio == nil ? 0x10 : 0x00,0])
    func word(_ value: Int) { var big = UInt32(value).bigEndian; withUnsafeBytes(of:&big) { data.append(contentsOf:$0) } }
    word(event); let name = Data(id.utf8); word(name.count); data.append(name)
    let payload = audio ?? (try! JSONSerialization.data(withJSONObject:body)); word(payload.count); data.append(payload); return data
}

private final class DoubaoOutput: PCMOutput {
    var onStarted: (() -> Void)?
    var onFinished: (() -> Void)?
    var onLevel: ((Double) -> Void)?
    var onUnderrun: (() -> Void)?
    var onFailure: (() -> Void)?
    var bytes = 0; var played = false; var stopped = false; var finished = false; var autoFinish = true
    func append(_ data: Data) throws { assert(!stopped); bytes += data.count }
    func play() throws { played = true; onStarted?() }
    func finish() throws { finished = true; if autoFinish { onFinished?() } }
    func stop() { stopped = true }
}

private final class DoubaoMockConnection: DoubaoConnection {
    var onOpen: (() -> Void)?
    var onMessage: ((Data) -> Void)?
    var onError: ((Error) -> Void)?
    var events: [Int] = []
    var texts: [String] = []
    var session = ""
    var sessionIDs: [String] = []
    var opens = 0
    var voice = ""
    var closed = false
    var rejected = false
    var delayClose = false
    var request: URLRequest?
    func open(_ request: URLRequest) {
        self.request = request; opens += 1
        DispatchQueue.main.async { [self] in
            if rejected { onError?(SpeechStreamError.http(403)) } else { onOpen?() }
        }
    }
    func send(_ data: Data, completion: @escaping (Error?) -> Void) {
        let bytes = Array(data); var cursor = 4
        func word() -> Int { let value = bytes[cursor..<cursor+4].reduce(0) { ($0 << 8) | Int($1) }; cursor += 4; return value }
        func block() -> Data { let size = word(); let result = Data(bytes[cursor..<cursor+size]); cursor += size; return result }
        assert(Array(bytes.prefix(4)) == [0x11,0x14,0x10,0])
        let event = word(); events.append(event)
        if event >= 100 { session = String(data:block(),encoding:.utf8)! }
        let body = try! JSONSerialization.jsonObject(with:block()) as! [String:Any]
        assert(cursor == bytes.count)
        if event == 100 {
            sessionIDs.append(session)
            let params = body["req_params"] as! [String:Any]
            voice = params["speaker"] as! String
            assert((params["audio_params"] as? [String:Any])?["sample_rate"] as? Int == 24000)
        }
        if event == 200 { texts.append((body["req_params"] as! [String:Any])["text"] as! String) }
        DispatchQueue.main.async { [self] in
            completion(nil); guard !closed else { return }
            switch event {
            case 1: onMessage?(serverFrame(50))
            case 100: onMessage?(serverFrame(150,id:session))
            case 200: onMessage?(serverFrame(352,id:session,audio:Data(repeating:0,count:9600)))
            case 102: onMessage?(serverFrame(152,id:session,body:["usage":["text_words":12]]))
            case 2: if !delayClose { onMessage?(serverFrame(52)) }
            default: break
            }
        }
    }
    func close() { closed = true }
}

func runDoubaoChecks() {
    func drain(_ delay: Double = 0.05) { RunLoop.current.run(until:Date(timeIntervalSinceNow:delay)) }
    let hello = try! DoubaoPacket.request(1)
    assert(Array(hello) == [0x11,0x14,0x10,0,0,0,0,1,0,0,0,2,0x7b,0x7d],"Connection request matches the documented wire bytes")
    let decoded = try! DoubaoPacket.decode(serverFrame(352,id:"test-session",audio:Data([1,0,2,0])))
    assert(decoded.event == 352 && decoded.identifier == "test-session" && decoded.payload == Data([1,0,2,0]))
    do { _ = try DoubaoPacket.decode(Data(hello.prefix(5))); assertionFailure("Truncated packet must fail") } catch {}
    var trailing = serverFrame(50); trailing.append(0)
    do { _ = try DoubaoPacket.decode(trailing); assertionFailure("Trailing bytes must fail") } catch {}
    var compressed = serverFrame(50); compressed[2] = 0x11
    do { _ = try DoubaoPacket.decode(compressed); assertionFailure("Unsupported compression must fail") } catch {}
    var errorFrame = Data([0x11,0xf0,0x10,0]); DoubaoPacket.put(45000000,into:&errorFrame); DoubaoPacket.put(2,into:&errorFrame); errorFrame.append(contentsOf:[0x7b,0x7d])
    do { _ = try DoubaoPacket.decode(errorFrame); assertionFailure("Cloud error must fail") }
    catch DoubaoSpeechError.rejected(let code) { assert(code == 45000000) } catch { assertionFailure("Wrong error") }
    let connection = DoubaoMockConnection(); let stream = DoubaoDuplexStream(connection:connection)
    var bytes = 0; var ended = false; var complete = false
    stream.onAudio = { assert($0.count <= 9600); bytes += $0.count }
    stream.onEnd = { _ in ended = true }; stream.onComplete = { assert($0 == nil); complete = true }
    stream.start(key:"mock-doubao-key",voice:DoubaoVoice.defaultID); try! stream.append("第一句话。")
    drain(); assert(bytes == 9600 && !ended && !complete,"Receive sound while input remains open")
    try! stream.append("第二句话。"); drain(); assert(bytes == 19200 && !ended)
    stream.finishInput(); drain(); assert(ended && complete && connection.closed)
    assert(connection.events == [1,100,200,200,102,2],"One connection and session carry multiple text chunks")
    assert(connection.request?.url?.scheme == "wss" && connection.request?.url?.host == "openspeech.bytedance.com")
    assert(connection.request?.url?.path == "/api/v3/tts/bidirection")
    assert(connection.request?.value(forHTTPHeaderField:"X-Api-Key") == "mock-doubao-key")
    assert(connection.request?.value(forHTTPHeaderField:"X-Api-Resource-Id") == "seed-tts-2.0")
    assert(connection.voice == DoubaoVoice.defaultID)
    let wrong = DoubaoMockConnection(); let wrongStream = DoubaoDuplexStream(connection:wrong); var wrongFailed = false
    wrongStream.onComplete = { wrongFailed = $0 != nil }; wrongStream.start(key:"mock",voice:DoubaoVoice.defaultID); drain()
    wrong.onMessage?(serverFrame(352,id:"different-session",audio:Data([0,0]))); assert(wrongFailed && wrong.closed)
    let empty = DoubaoMockConnection(); let emptyStream = DoubaoDuplexStream(connection:empty); var emptyFailed = false
    emptyStream.onComplete = { emptyFailed = $0 != nil }; emptyStream.start(key:"mock",voice:DoubaoVoice.defaultID); drain()
    empty.onMessage?(serverFrame(152,id:empty.session)); assert(emptyFailed,"Early/empty session finish must fail")
    let suite = "whale-doubao-test-\(UUID().uuidString)"; let defaults = UserDefaults(suiteName:suite)!
    defer { defaults.removePersistentDomain(forName:suite) }
    let settings = ProactiveSettings(defaults:defaults); settings.proactive = true; settings.quietStart = 0; settings.quietEnd = 0
    var outputs: [DoubaoOutput] = []; var sockets: [DoubaoMockConnection] = []; var rejectNext = false
    let pipeline = VoicePipeline(settings:settings,credential:"mock-doubao-key",recording:false,makePCMPlayer:{ let output = DoubaoOutput(); outputs.append(output); return output },makeDoubaoStream:{
        let socket = DoubaoMockConnection(); socket.rejected = rejectNext; sockets.append(socket); return DoubaoDuplexStream(connection:socket)
    })
    var failures: [String] = []
    pipeline.onTestFailure = { failures.append($0) }
    pipeline.receive(["type":"start","turn":"duplex-test","startedAt":Date().timeIntervalSince1970*1000])
    pipeline.receive(["type":"sentence","turn":"duplex-test","index":0,"text":"第一句固定测试。"]); drain()
    assert(outputs.count == 1 && outputs[0].played && !outputs[0].finished)
    pipeline.receive(["type":"sentence","turn":"duplex-test","index":1,"text":"第二句固定测试。"]); drain()
    assert(sockets.count == 1 && outputs[0].bytes == 19200)
    pipeline.receive(["type":"end","turn":"duplex-test"]); drain()
    assert(outputs[0].finished && pipeline.status == "Doubao connected · streaming ready")
    pipeline.receive(["type":"start","turn":"cancel-test","startedAt":Date().timeIntervalSince1970*1000])
    pipeline.receive(["type":"sentence","turn":"cancel-test","index":0,"text":"等待后续的测试。"]); drain()
    let cancelled = outputs.last!, cancelledSocket = sockets.last!
    pipeline.cancel(); drain(); assert(cancelled.stopped && cancelledSocket.events.contains(101) && cancelledSocket.closed)
    let count = cancelled.bytes; cancelledSocket.onMessage?(serverFrame(352,id:cancelledSocket.session,audio:Data([0,0]))); assert(cancelled.bytes == count,"Late audio is ignored")
    pipeline.receive(["type":"proactive","event":["id":"doubao-dnd","text":"固定提醒。","kind":"decision","priority":1,"expiresAt":Date().timeIntervalSince1970*1000+60000]])
    settings.setDND(minutes:30); pipeline.settingsChanged(); drain()
    assert(outputs.last!.stopped && !pipeline.isPlaying)
    let total = sockets.count; settings.setDND(minutes:0); pipeline.settingsChanged(); drain(); assert(sockets.count == total,"No replay")
    rejectNext = true; pipeline.testVoice(); drain()
    assert(pipeline.status.contains("HTTP 403") && failures.count == 1 && failures[0].contains("HTTP 403")); let failed = sockets.count
    pipeline.testVoice(); drain(); assert(sockets.count == failed && failures.count == 1,"No retry or duplicate error after clearing a rejected key")
    assert(!defaults.dictionaryRepresentation().values.contains { String(describing:$0).contains("mock-doubao-key") })
    pipeline.disconnect(); assert(pipeline.status == "Voice disconnected")
    let configFolder = FileManager.default.temporaryDirectory.appendingPathComponent("whale-config-pipeline-" + UUID().uuidString)
    try! FileManager.default.createDirectory(at:configFolder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer { try? FileManager.default.removeItem(at:configFolder) }
    let config = configFolder.appendingPathComponent("voice-config.local.json")
    try! Data("{\"doubao_api_key\":\"mock-config-key\"}".utf8).write(to:config)
    let beforeLoad = sockets.count
    assert(try! pipeline.loadVoiceConfig(from:config))
    assert(pipeline.status == "Doubao key set · select Test Voice" && sockets.count == beforeLoad,"Loading a config makes no cloud request")
    rejectNext = false; pipeline.testVoice(); drain()
    assert(sockets.last!.request?.value(forHTTPHeaderField:"X-Api-Key") == "mock-config-key")
    assert(pipeline.status == "Doubao connected · streaming ready")
    try! Data("{\"doubao_api_key\":123}".utf8).write(to:config)
    do { _ = try pipeline.loadVoiceConfig(from:config); assertionFailure("Invalid reload must fail") } catch {}
    pipeline.testVoice(); drain()
    assert(sockets.last!.request?.value(forHTTPHeaderField:"X-Api-Key") == "mock-config-key","Invalid reload preserves the working key")
    pipeline.disconnect()
    let beforeDisconnect = sockets.count; pipeline.testVoice(); drain()
    assert(sockets.count == beforeDisconnect,"Disconnect must not reload the file automatically")
    let transport = DoubaoSocket(); var redirected = true
    let session = URLSession(configuration:.ephemeral); defer { session.invalidateAndCancel() }
    let request = URLRequest(url:URL(string:"https://openspeech.bytedance.com")!)
    transport.urlSession(session,task:session.dataTask(with:request),willPerformHTTPRedirection:HTTPURLResponse(url:request.url!,statusCode:302,httpVersion:nil,headerFields:nil)!,newRequest:URLRequest(url:URL(string:"https://example.invalid")!)) { redirected = $0 != nil }
    assert(!redirected)
    var callEvents: [[String:Any]] = [], callOutputs: [DoubaoOutput] = [], callSockets: [DoubaoMockConnection] = []
    let caller = VoicePipeline(settings:settings,credential:"mock-call-key",recording:false,makePCMPlayer:{
        let output = DoubaoOutput(); output.autoFinish = false; callOutputs.append(output); return output
    },makeDoubaoStream:{ let socket = DoubaoMockConnection(); callSockets.append(socket); return DoubaoDuplexStream(connection:socket) })
    caller.onCallState = { callEvents.append($0) }
    caller.selectVoice(DoubaoVoice.choices[3].id)
    caller.receive(["type":"call_open","id":"mock-call"])
    assert(callEvents.last?["phase"] as? String == "ready")
    caller.receive(["type":"start","turn":"unrelated"])
    assert(!caller.isPlaying,"Other bound replies cannot interrupt a call")
    caller.receive(["type":"call_prepare","id":"mock-call"]); drain()
    assert(callSockets.count == 1 && callSockets[0].events == [1], "Question submission preconnects without starting synthesis")
    caller.receive(["type":"start","turn":"call-turn","callId":"mock-call"])
    caller.receive(["type":"sentence","turn":"call-turn","index":0,"text":"固定通话测试。"]); drain()
    assert(callEvents.last?["phase"] as? String == "speaking")
    assert(callSockets[0].voice == DoubaoVoice.choices[3].id,"Calls reuse the selected whale voice")
    callSockets[0].delayClose = true
    caller.receive(["type":"end","turn":"call-turn"]); drain()
    assert(callOutputs[0].finished && !callEvents.contains { $0["phase"] as? String == "finished" },"Model/TTS completion must not reopen the microphone before audio drains")
    callOutputs[0].onFinished?(); drain()
    assert(callEvents.last?["phase"] as? String == "finished", "Audio drain must not wait for WebSocket ConnectionFinished")
    assert(!callSockets[0].closed && callSockets[0].events == [1,100,200,102], "Finished speech keeps its WebSocket alive")
    let firstSession = callSockets[0].session
    caller.receive(["type":"call_prepare","id":"mock-call"])
    caller.receive(["type":"start","turn":"second-call-turn","callId":"mock-call"])
    caller.receive(["type":"sentence","turn":"second-call-turn","index":0,"text":"第二轮复用连接。"]); drain()
    assert(callSockets.count == 1 && callSockets[0].opens == 1 && callSockets[0].sessionIDs.count == 2)
    assert(callSockets[0].session != firstSession, "Each reply uses a fresh synthesis session ID")
    let bytesBeforeLate = callOutputs[1].bytes
    callSockets[0].onMessage?(serverFrame(352,id:firstSession,audio:Data(repeating:0,count:9600)))
    assert(callOutputs[1].bytes == bytesBeforeLate, "Retired session audio cannot enter a new reply")
    caller.receive(["type":"end","turn":"second-call-turn"]); drain()
    callOutputs[1].onFinished?(); drain()
    assert(callEvents.last?["phase"] as? String == "finished")
    let statusesBeforeIdleLoss = callEvents.count
    callSockets[0].onError?(DoubaoSpeechError.truncated)
    assert(callEvents.count == statusesBeforeIdleLoss, "Idle network loss does not fail completed speech")
    caller.receive(["type":"call_prepare","id":"mock-call"]); drain()
    assert(callSockets.count == 2 && callSockets[1].events == [1], "Next question reconnects after idle socket loss")
    caller.expireWarmConnection(at:Date().timeIntervalSince1970 * 1000 + 119000); drain()
    assert(!callSockets[1].closed)
    caller.expireWarmConnection(at:Date().timeIntervalSince1970 * 1000 + 121000); drain()
    assert(callSockets[1].closed, "Two minutes of inactivity closes the idle connection")
    caller.receive(["type":"call_prepare","id":"mock-call"]); drain()
    assert(callSockets.count == 3, "An expired connection can be replaced")
    caller.receive(["type":"start","turn":"failed-turn","callId":"mock-call"])
    caller.receive(["type":"sentence","turn":"failed-turn","index":0,"text":"中途错误不重播。"]); drain()
    let attemptsBeforeFailure = callSockets.count
    callSockets.last!.onError?(DoubaoSpeechError.truncated); drain()
    assert(callEvents.last?["phase"] as? String == "failed" && callSockets.last!.closed)
    assert(callSockets.count == attemptsBeforeFailure && callOutputs.last!.stopped, "Active failure stops audio without automatic retry")
    caller.receive(["type":"call_resume","id":"mock-call"])
    caller.receive(["type":"start","turn":"paused-turn","callId":"mock-call"])
    caller.receive(["type":"sentence","turn":"paused-turn","index":0,"text":"暂停测试。"]); drain()
    caller.receive(["type":"call_pause","id":"wrong-call"])
    assert(caller.isPlaying)
    caller.receive(["type":"call_pause","id":"mock-call"])
    assert(!caller.isPlaying && callOutputs.last!.stopped)
    let countBeforePause = callSockets.count
    caller.receive(["type":"start","turn":"late-turn","callId":"mock-call"])
    caller.receive(["type":"sentence","turn":"late-turn","index":0,"text":"不得播放。"]); drain()
    assert(callSockets.count == countBeforePause)
    caller.receive(["type":"call_resume","id":"mock-call"])
    caller.receive(["type":"start","turn":"lease-turn","callId":"mock-call"])
    caller.receive(["type":"sentence","turn":"lease-turn","index":0,"text":"超时测试。"]); drain()
    caller.expireCall(at:Date().timeIntervalSince1970 * 1000 + 16000)
    assert(!caller.isPlaying && callOutputs.last!.stopped && callEvents.last?["phase"] as? String == "closed")
    caller.receive(["type":"start","turn":"late-after-close","callId":"mock-call"])
    assert(!caller.isPlaying,"Closed calls cannot restart audio")
    print("Connection reuse checks passed: question-time warmup, one socket/two unique sessions, retired audio isolation, idle loss/reconnect and 120-second expiry (mock only).")
    print("Whale call checks passed: selected voice, exclusive playback, actual audio-drain acknowledgement, pause/cancel, stale-call rejection and lease expiry (mock only).")
    print("Doubao duplex checks passed: wire fixtures, strict framing/session IDs, one session with multiple text chunks and early audio, cancel/stale rejection, DND/no replay, permission failure/no retry and redirect refusal (mock only).")
}
