import Foundation

private final class MockMicrophone: MicrophoneInput {
    var onAudio: ((Data) -> Void)?
    var onLevel: ((Double) -> Void)?
    var onFailure: (() -> Void)?
    var starts = 0, stops = 0
    var holdPermission = false
    var permission: ((Bool) -> Void)?
    func start(completion: @escaping (Bool) -> Void) {
        starts += 1
        if holdPermission { permission = completion } else { completion(true) }
    }
    func stop() { stops += 1 }
}

func runNativeCallChecks() {
    let microphone = MockMicrophone(), call = NativeCallController(microphone:microphone)
    var messages: [[String:Any]] = [], states: [String] = []
    var now = 1000.0
    call.now = { now }; call.send = { messages.append($0) }; call.onChange = { states.append($0); _ = $1 }
    func receive(_ phase: String) { call.receive(["type":"native_state","token":call.token!,"id":"test-call","phase":phase]) }
    func drain() { RunLoop.current.run(until:Date(timeIntervalSinceNow:0.4)) }
    call.toggle(); assert(call.phase == "connecting" && microphone.starts == 0)
    receive("connecting"); receive("ready"); drain()
    assert(call.phase == "listening" && microphone.starts == 1)
    call.tick(); assert(messages.last?["action"] as? String == "ping")
    microphone.onAudio?(SpeechSegmenter.wave(Data(repeating:0,count:64000)))
    assert(call.phase == "transcribing")
    assert(messages.filter { $0["action"] as? String == "audio_chunk" }.count == 3)
    receive("generating"); assert(call.phase == "thinking" && microphone.starts == 1)
    receive("speaking"); assert(call.phase == "speaking" && microphone.starts == 1)
    receive("finished"); drain(); assert(call.phase == "listening" && microphone.starts == 2)
    call.pause(); receive("paused"); assert(call.phase == "paused")
    now += 100; call.resume(); receive("connecting"); call.tick()
    assert(call.phase == "connecting", "Resume gets a fresh startup deadline")
    receive("ready"); drain(); assert(call.phase == "listening")
    now += 9; call.tick(); assert(!call.isOpen && call.phase == "failed")
    microphone.holdPermission = true
    call.toggle(); receive("ready"); drain(); assert(call.phase == "permission")
    let token = call.token!
    call.end(); microphone.permission?(true)
    call.receive(["type":"native_state","token":token,"id":"old-call","phase":"ready"])
    drain(); assert(!call.isOpen && call.phase == "idle")
    let clicks = CharacterClicks(); var pokes = 0
    clicks.single(after:0.01) { pokes += 1 }; clicks.cancel()
    RunLoop.current.run(until:Date(timeIntervalSinceNow:0.03))
    assert(pokes == 0, "The second click cancels the pending single-click reaction")
    assert(Set(["listening","thinking","speaking","paused"].map { CallAppearance.forPhase($0).title }).count == 4)
    assert(states.contains("listening") && states.contains("thinking") && states.contains("speaking"))
    print("Native call checks passed: microphone/state ordering, multi-turn playback drain, pause/resume, offline timeout, late permission/results and single/double-click arbitration (mock microphone).")
}
