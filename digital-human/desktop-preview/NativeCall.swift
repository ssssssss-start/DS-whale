import Foundation

final class NativeCallController {
    let microphone: MicrophoneInput
    var send: (([String:Any]) -> Void)?
    var onChange: ((String,String) -> Void)?
    var onLevel: ((Double) -> Void)?
    private(set) var phase = "idle"
    private(set) var token: String?
    private var lastHost = 0.0
    private var began = 0.0
    private var generation = 0
    private var lastReason = ""
    var now: () -> Double = { Date().timeIntervalSince1970 }
    var isOpen: Bool { token != nil }
    init(microphone: MicrophoneInput = VoiceCapture()) {
        self.microphone = microphone
        microphone.onLevel = { [weak self] in self?.onLevel?($0) }
        microphone.onAudio = { [weak self] in self?.upload($0) }
        microphone.onFailure = { [weak self] in self?.pause("Microphone changed or disconnected. Check your input device, then resume the call.") }
    }
    private func change(_ value: String, _ reason: String = "") {
        let detail = value == "paused" && phase == "paused" && reason.isEmpty ? lastReason : reason
        phase = value; lastReason = detail; onChange?(value,detail)
    }
    func toggle() {
        if isOpen { end(); return }
        token = UUID().uuidString; began = now(); lastHost = now(); generation += 1
        change("connecting"); command("start")
    }
    private func command(_ action: String, extra: [String:Any] = [:]) {
        guard let token else { return }
        var message = extra; message["type"] = "native_call"; message["token"] = token; message["action"] = action
        send?(message)
    }
    func receive(_ message: [String:Any]) {
        guard message["type"] as? String == "native_state", let token, message["token"] as? String == token,
              let state = message["phase"] as? String else { return }
        lastHost = now()
        switch state {
        case "closed": finish()
        case "ready", "finished": listen()
        case "waiting", "generating": microphone.stop(); generation += 1; change("thinking")
        case "transcribing": microphone.stop(); change("transcribing")
        case "speaking": microphone.stop(); generation += 1; change("speaking")
        case "failed" where message["id"] as? String == nil:
            finish(); change("failed",message["reason"] as? String ?? "Harness voice is unavailable.")
        case "paused", "failed", "cancelled":
            microphone.stop(); generation += 1
            change("paused",message["reason"] as? String ?? "Voice call paused. Choose Resume Voice Call.")
        case "connecting": if phase != "connecting" { microphone.stop(); change("connecting") }
        default: break
        }
    }
    private func listen() {
        guard isOpen, !["listening","permission"].contains(phase) else { return }
        generation += 1; let own = generation
        change("permission")
        // Let the output device drain before opening the microphone again.
        DispatchQueue.main.asyncAfter(deadline:.now()+0.35) { [weak self] in
            guard let self, self.isOpen, self.generation == own else { return }
            self.microphone.start { [weak self] good in
                guard let self, self.isOpen, self.generation == own else { return }
                if good { self.change("listening"); self.command("input_state",extra:["phase":"listening"]) }
                else { self.pause("Microphone unavailable. Allow Whale Companion in macOS Privacy & Security → Microphone.") }
            }
        }
    }
    private func upload(_ audio: Data) {
        guard isOpen, phase == "listening", audio.count >= 46, audio.count <= 640044 else { return }
        microphone.stop(); generation += 1; change("transcribing")
        let recording = UUID().uuidString
        command("audio_begin",extra:["recording":recording])
        for (seq,offset) in stride(from:0,to:audio.count,by:32000).enumerated() {
            command("audio_chunk",extra:["recording":recording,"seq":seq,"data":audio.subdata(in:offset..<min(offset+32000,audio.count)).base64EncodedString()])
        }
        command("audio_end",extra:["recording":recording])
    }
    func pause(_ reason: String = "") { guard isOpen else { return }; microphone.stop(); generation += 1; change("paused",reason); command("pause") }
    func resume() { guard isOpen else { return }; microphone.stop(); generation += 1; began = now(); change("connecting"); command("resume") }
    func tick() {
        guard isOpen else { return }
        if now() - lastHost > 8 || (phase == "connecting" && now() - began > 10) {
            command("end"); finish(); change("failed","Harness voice plugin is unavailable. Keep Harness running in the background."); return
        }
        command("ping")
    }
    func end() { command("end"); finish() }
    private func finish() { microphone.stop(); generation += 1; token = nil; change("idle") }
}
