import Foundation

private final class MockSpeechProtocol: URLProtocol {
    static var requests = 0
    static var stopped = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        DispatchQueue.global().asyncAfter(deadline:.now()+0.05) { [self] in
            // Deliberately deliver a late result even after cancellation.
            let response = HTTPURLResponse(url:request.url!, statusCode:200,httpVersion:nil,headerFields:["Content-Type":"audio/mpeg"])!
            client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:Data("mock audio; must never reach playback".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { Self.stopped += 1 }
}

func runVoicePolicyChecks() {
    let suite = "whale-policy-test-\(UUID().uuidString)"
    let isolated = UserDefaults(suiteName:suite)!
    defer { isolated.removePersistentDomain(forName:suite) }
    let settings = ProactiveSettings(defaults:isolated)
    settings.proactive = true; settings.quietStart = 0; settings.quietEnd = 0
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockSpeechProtocol.self]
    let session = URLSession(configuration:configuration)
    defer { session.invalidateAndCancel() }
    let pipeline = VoicePipeline(settings:settings,session:session,credential:"mock-local-password",provider:.mira,recording:false)
    var acknowledgements: [(String,String)] = []
    pipeline.onAcknowledgement = { acknowledgements.append(($0,$1)) }
    func event(_ id:String) -> [String:Any] {
        ["type":"proactive", "event":["id":id,"text":"测试提示。","kind":"decision","priority":1,"expiresAt":Date().timeIntervalSince1970*1000+60000]]
    }
    func drain(_ seconds:Double) { RunLoop.current.run(until:Date(timeIntervalSinceNow:seconds)) }
    settings.setDND(minutes:30)
    pipeline.receive(event("blocked"));drain(0.02)
    assert(acknowledgements.contains { $0 == ("blocked","dropped") })
    assert(MockSpeechProtocol.requests == 0,"DND must prevent synthesis")
    settings.setDND(minutes:0)
    pipeline.receive(event("inflight"));drain(0.02)
    assert(MockSpeechProtocol.requests == 1)
    settings.setDND(minutes:30);pipeline.settingsChanged();drain(0.1)
    assert(acknowledgements.contains { $0 == ("inflight","cancelled") })
    assert(!acknowledgements.contains { $1 == "playing" },"Late synthesis result must not start playback")
    settings.setDND(minutes:0);pipeline.settingsChanged();drain(0.02)
    assert(MockSpeechProtocol.requests == 1,"DND expiry must not replay old content")
    settings.setDND(minutes:30)
    pipeline.receive(["type":"start","turn":"direct-test","startedAt":Date().timeIntervalSince1970*1000])
    assert(pipeline.isPlaying,"A user-requested direct turn remains allowed during DND")
    pipeline.receive(event("queued-during-dnd"))
    assert(acknowledgements.contains { $0 == ("queued-during-dnd","dropped") })
    pipeline.cancel()
    print("Voice policy checks passed: synthesis gate, in-flight cancellation, stale result rejection, no replay and direct-turn exemption (mock transport only).")
}
