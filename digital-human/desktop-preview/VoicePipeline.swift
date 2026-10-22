import AppKit
import AVFoundation
import Darwin

// Same-user Unix socket: no browser-accessible port and no upstream credentials in IPC.
final class VoiceSocket {
    static let directory = URL(fileURLWithPath: "/tmp/whale-voice-\(getuid())", isDirectory: true)
    static let path = directory.appendingPathComponent("speech.sock").path
    private let folder: URL
    private var endpoint: String { folder.appendingPathComponent("speech.sock").path }
    init(folder: URL = VoiceSocket.directory) { self.folder = folder }
    private var descriptor: Int32 = -1
    private var clients = Set<Int32>()
    private let lock = NSLock()
    private let writer = DispatchQueue(label: "whale.ipc.writer")
    func send(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(10)
        writer.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            data.withUnsafeBytes { raw in
                for fd in self.clients {
                    var offset = 0
                    while offset < data.count {
                        let count = Darwin.send(fd, raw.baseAddress!.advanced(by:offset), data.count - offset, 0)
                        if count > 0 { offset += count }
                        else if errno != EINTR { shutdown(fd,SHUT_RDWR); break }
                    }
                }
            }
        }
    }
    func start(receive: @escaping ([String: Any]) -> Void) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: folder.path) {
            try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        let attributes = try fm.attributesOfItem(atPath: folder.path)
        guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              attributes[.type] as? FileAttributeType == .typeDirectory else { throw VoiceError.unavailable }
        chmod(folder.path, 0o700)
        // The previous app instance owns the same endpoint; a new launch replaces it.
        unlink(endpoint)
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw VoiceError.unavailable }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let fd = descriptor
        let bytes = Array(endpoint.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue:address.sun_path) else { close(fd); descriptor = -1; throw VoiceError.unavailable }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in raw.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }) }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0, listen(fd, 4) == 0 else { close(fd); descriptor = -1; throw VoiceError.unavailable }
        chmod(endpoint, 0o600)
        DispatchQueue.global(qos: .utility).async {
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { break }
                self.lock.lock(); let full = self.clients.count >= 4; self.lock.unlock()
                if full { close(client); continue }
                var timeout = timeval(tv_sec:1,tv_usec:0)
                setsockopt(client,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
                var noSignal: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
                self.lock.lock(); self.clients.insert(client); self.lock.unlock()
                DispatchQueue.global(qos: .utility).async {
                    defer { self.lock.lock(); self.clients.remove(client); close(client); self.lock.unlock() }
                    var pending = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                    while true {
                        let count = read(client, &buffer, buffer.count)
                        if count <= 0 { break }
                        pending.append(contentsOf: buffer.prefix(count))
                        if pending.count > 65536 { break }
                        while let end = pending.firstIndex(of: 10) {
                            let line = pending.prefix(upTo: end)
                            pending.removeSubrange(...end)
                            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                                DispatchQueue.main.async { receive(object) }
                            }
                        }
                    }
                }
            }
        }
    }
    func stop() {
        if descriptor >= 0 { shutdown(descriptor, SHUT_RDWR); close(descriptor); descriptor = -1 }
        lock.lock(); for fd in clients { shutdown(fd,SHUT_RDWR) }; lock.unlock()
    }
    deinit { stop() }
}

enum VoiceError: Error { case unavailable }

final class VoicePipeline: NSObject, AVAudioPlayerDelegate {
    struct Sentence {
        let index: Int
        let text: String
        let receivedAt: Double
        let firstTextAt: Double?
        let sentenceAt: Double?
    }
    struct Clip { let sentence: Sentence; let data: Data; let synthesizedAt: Double; let synthesisMS: Double; let cached: Bool }
    private final class StreamClip {
        let sentence: Sentence
        let audio: PCMOutput
        let began: Double
        var firstPacket: Double?
        init(_ sentence: Sentence, _ audio: PCMOutput, _ began: Double) { self.sentence = sentence; self.audio = audio; self.began = began }
    }
    private let socket = VoiceSocket()
    private let session: URLSession
    private let makePCMPlayer: () -> PCMOutput
    private let makeDoubaoStream: () -> DoubaoDuplexStream
    private var doubaoStream: DoubaoDuplexStream?
    private let recording: Bool
    private let provider: VoiceProvider
    private var doubaoVerified = false
    var selectedVoice = DoubaoVoice.defaultID
    private var serviceName: String { provider == .doubao ? "Doubao" : "Mira" }
    private var idleStatus: String {
        if password.isEmpty { return "Voice disconnected" }
        if provider == .doubao { return doubaoVerified ? "Doubao connected · streaming ready" : "Doubao key set · select Test Voice" }
        return streamingSupported ? "Mira connected · streaming ready" : "Mira connected · waiting for replies"
    }
    private var streamingSupported: Bool
    private var streamRequest: SpeechStream?
    private var streamLoading: StreamClip?
    private var streamReady: [StreamClip] = []
    private var streamPlaying: StreamClip?
    private var password = ""
    private var turn = ""
    private var startedAt = 0.0
    private var pending: [Sentence] = []
    private var doubaoAudioEnded = false
    private var warmDoubao: DoubaoDuplexStream?
    private var warmTouched = 0.0
    private var ready: [Clip] = []
    private var task: URLSessionDataTask?
    private var player: AVAudioPlayer?
    private var playing: Clip?
    private var generation = UUID()
    private var inputEnded = false
    private var previousEndedAt: Double?
    private var meter: Timer?
    private var firstPlay = true
    private var report: URL?
    let proactiveSettings: ProactiveSettings
    private var proactiveQueue: [[String: Any]] = []
    private var currentEvent: [String: Any]?
    private var stateTimer: Timer?
    private var latestInbox: [String: Any] = [:]
    private var callID: String?
    private var callDeadline = 0.0
    private var callPaused = false
    var onCallState: (([String: Any]) -> Void)?
    var onAcknowledgement: ((String, String) -> Void)?
    var onInbox: (([String: Any]) -> Void)?
    var onProactivePlayback: ((String) -> Void)?
    var onHostStatus: ((String) -> Void)?
    var onTestFailure: ((String) -> Void)?
    init(settings: ProactiveSettings = ProactiveSettings(), session: URLSession = URLSession(configuration:.ephemeral), credential: String = "",
         provider: VoiceProvider = .doubao, streaming: Bool = false, recording: Bool = true,
         makePCMPlayer: @escaping () -> PCMOutput = { PCMPlayback() }, makeDoubaoStream: @escaping () -> DoubaoDuplexStream = { DoubaoDuplexStream() }) {
        self.proactiveSettings = settings; self.session = session; self.password = credential
        self.provider = provider; self.streamingSupported = streaming || provider == .doubao
        self.makePCMPlayer = makePCMPlayer; self.recording = recording; self.makeDoubaoStream = makeDoubaoStream; super.init()
    }
    var isPlaying: Bool { player != nil || !turn.isEmpty }
    func sendControl(_ action: String, id: String? = nil) {
        var value: [String: Any] = ["type":"control", "action":action]
        if let id { value["id"] = id }
        socket.send(value)
    }
    func publishState() {
        var state = proactiveSettings.snapshot(playing: isPlaying)
        state["voiceProtocol"] = 1
        state["voiceReady"] = provider == .doubao && !password.isEmpty && !muted && proactiveSettings.visible
        socket.send(state)
    }
    private func callState(_ phase: String, id: String? = nil, turn: String? = nil) {
        guard let id = id ?? callID else { return }
        var state: [String: Any] = ["type":"call_state", "id":id, "phase":phase]
        if let turn { state["turn"] = turn }
        onCallState?(state); socket.send(state)
    }
    func expireCall(at time: Double = Date().timeIntervalSince1970 * 1000) {
        if callID != nil && time > callDeadline { endCall() }
    }
    private func prepareDoubao() -> DoubaoDuplexStream {
        warmTouched = now
        if let warmDoubao, warmDoubao.reusable { return warmDoubao }
        warmDoubao?.cancel()
        let stream = makeDoubaoStream(); stream.keepAlive = true; warmDoubao = stream
        stream.prepare(key:password)
        return stream
    }
    func expireWarmConnection(at time: Double = Date().timeIntervalSince1970 * 1000) {
        guard !isPlaying, time - warmTouched >= 120000 else { return }
        warmDoubao?.cancel(); warmDoubao = nil
    }
    private func endCall() {
        cancel(); callState("closed"); callID = nil; callPaused = false; callDeadline = 0
    }
    func settingsChanged() {
        if let reason = proactiveSettings.reason {
            for event in proactiveQueue { acknowledge(event, "dropped", reason) }
            proactiveQueue.removeAll()
            if currentEvent != nil { cancel() }
        }
        publishState()
    }
    private func acknowledge(_ event: [String: Any], _ status: String, _ reason: String = "") {
        guard let id = event["id"] as? String else { return }
        onAcknowledgement?(id, status)
        socket.send(["type":"ack", "id":id, "status":status, "reason":reason])
    }
    private func queueProactive(_ event: [String: Any]) {
        guard let id = event["id"] as? String, let text = event["text"] as? String, !text.isEmpty, text.count <= 500,
              let expires = event["expiresAt"] as? Double else { return }
        if callID != nil { acknowledge(event,"dropped","voice_call"); return }
        if expires <= now { acknowledge(event,"dropped","expired"); return }
        if currentEvent?["id"] as? String == id || proactiveQueue.contains(where: { $0["id"] as? String == id }) { return }
        if let reason = proactiveSettings.reason { acknowledge(event, "dropped", reason); return }
        if password.isEmpty { acknowledge(event, "failed", "voice_disconnected"); return }
        let kind = event["kind"] as? String ?? ""
        if kind == "companion" && isPlaying { acknowledge(event, "dropped", "busy"); return }
        if currentEvent?["kind"] as? String == "companion", (event["priority"] as? Int ?? 2) < 3 { cancel() }
        if proactiveQueue.count >= 3 {
            if let index = proactiveQueue.firstIndex(where: { $0["kind"] as? String == "companion" }) {
                acknowledge(proactiveQueue.remove(at: index), "dropped", "queue_full")
            } else { acknowledge(event, "dropped", "queue_full"); return }
        }
        proactiveQueue.append(event)
        proactiveQueue.sort { ($0["priority"] as? Int ?? 2) < ($1["priority"] as? Int ?? 2) }
        acknowledge(event, "queued"); startNextProactive()
    }
    private func startNextProactive() {
        guard turn.isEmpty else { return }
        while !proactiveQueue.isEmpty {
            let event = proactiveQueue.removeFirst()
            if let reason = proactiveSettings.reason { acknowledge(event, "dropped", reason); continue }
            if (event["expiresAt"] as? Double ?? 0) <= now { acknowledge(event, "dropped", "expired"); continue }
            currentEvent = event
            turn = "proactive:" + (event["id"] as? String ?? UUID().uuidString)
            startedAt = now; generation = UUID(); firstPlay = true; inputEnded = true; previousEndedAt = nil
            report = nil
            pending = [Sentence(index:0, text:event["text"] as! String, receivedAt:now, firstTextAt:nil, sentenceAt:nil)]
            acknowledge(event, "synthesizing"); onStart?(); synthesizeNext(); return
        }
    }
    func stopAll() {
        for event in proactiveQueue { acknowledge(event,"cancelled","user_stop") }
        proactiveQueue.removeAll(); cancel(); sendControl("stop")
    }
    var onLevel: ((Double) -> Void)?
    var onStatus: ((String) -> Void)?
    var onStart: (() -> Void)?
    var muted = false { didSet { if muted { cancel() } } }
    private var now: Double { Date().timeIntervalSince1970 * 1000 }
    private(set) var status = "Voice disconnected"
    private func setStatus(_ value: String) { status = value; onStatus?(value) }

    func start() {
        do { try socket.start { [weak self] in self?.receive($0) } }
        catch { setStatus("Voice socket unavailable"); onHostStatus?("Desktop IPC unavailable; restart the companion") }
        stateTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.expireCall(); self.expireWarmConnection()
            self.proactiveSettings.expire(); self.settingsChanged()
        }
    }
    func connect() {
        if provider == .doubao { connectDoubao(); return }
        let alert = NSAlert()
        alert.messageText = "Connect Mira voice"
        alert.informativeText = "Enter the local service password you set in start.py. It stays in memory until this app quits. The service must be running on 127.0.0.1:8769."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
        password = field.stringValue
        field.stringValue = ""
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8769/healthz")!)
        request.timeoutInterval = 5
        request.setValue("Bearer " + password, forHTTPHeaderField: "Authorization")
        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if error != nil { self.setStatus("Mira service unavailable"); return }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    self.password = ""; self.setStatus("Local password rejected"); return
                }
                let health = data.flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Any] }
                self.streamingSupported = (health?["capabilities"] as? [String:Any])?["pcm_stream"] as? Int == 1
                self.setStatus(self.streamingSupported ? "Mira connected · streaming ready" : "Mira connected · waiting for replies")
            }
        }.resume()
    }
    private func connectDoubao() {
        let alert = NSAlert()
        alert.messageText = "Connect Doubao Voice"
        alert.informativeText = "Enter a Speech API Key from the Volcengine Doubao Voice console for this run, or put it in voice-config.local.json beside the app to load it on every launch. This input does not write to that file. Choose Test Voice to hear a short sample (billed by your account)."
        let input = VoiceKeyInput(), field = input.field
        alert.accessoryView = input; alert.addButton(withTitle:"Connect"); alert.addButton(withTitle:"Cancel")
        NSApp.activate(ignoringOtherApps:true); alert.window.initialFirstResponder = field
        defer { field.stringValue = "" }
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let key = field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("\n"), !key.contains("\r") else { return }
        cancel(); password = key; doubaoVerified = false; setStatus(idleStatus)
    }
    @discardableResult
    func loadVoiceConfig(from url: URL = VoiceConfig.url) throws -> Bool {
        guard provider == .doubao, let key = try VoiceConfig.load(from:url) else { return false }
        cancel(); password = key; doubaoVerified = false; setStatus(idleStatus)
        return true
    }
    func selectVoice(_ id: String) {
        guard DoubaoVoice.choices.contains(where: { $0.id == id }) else { return }
        cancel(); selectedVoice = id; doubaoVerified = false; setStatus(idleStatus)
    }
    func disconnect() { cancel(); password = ""; doubaoVerified = false; setStatus(idleStatus) }
    func testVoice() {
        guard provider == .doubao else { return }
        let id = "voice-preview:" + UUID().uuidString
        receive(["type":"start","turn":id,"startedAt":now])
        receive(["type":"sentence","turn":id,"index":0,"text":"你好呀，我是鲸鱼娘。现在用甜美的声音陪你说话。"])
        receive(["type":"end","turn":id])
    }
    func receive(_ object: [String: Any]) {
        guard let kind = object["type"] as? String else { return }
        expireCall()
        if kind == "call_open", let id = object["id"] as? String, id.count <= 200 {
            if callID != nil && callID != id { callState("failed",id:id); return }
            guard provider == .doubao, !password.isEmpty, !muted, proactiveSettings.visible else { callState("failed",id:id); return }
            for event in proactiveQueue { acknowledge(event,"dropped","voice_call") }
            proactiveQueue.removeAll(); cancel(); callID = id; callPaused = false; callDeadline = now + 15000
            callState("ready"); return
        }
        if ["call_ping","call_prepare","call_pause","call_resume","call_close"].contains(kind) {
            guard let id = object["id"] as? String, id == callID else { return }
            if kind == "call_close" { endCall(); return }
            callDeadline = now + 15000
            if kind == "call_prepare", !callPaused, !password.isEmpty, !muted, !isPlaying { _ = prepareDoubao() }
            if kind == "call_pause" { cancel(); callPaused = true; callState("paused") }
            if kind == "call_resume" { callPaused = false; callState("ready") }
            return
        }
        if kind == "hello" { publishState(); return }
        if kind == "inbox" { latestInbox = object; onInbox?(object); return }
        if kind == "host_status" { onHostStatus?(object["text"] as? String ?? ""); return }
        if kind == "dnd_command" {
            let minutes = object["minutes"] as? Int ?? 30
            proactiveSettings.setDND(minutes: minutes == -1 ? nil : minutes); settingsChanged(); return
        }
        if kind == "proactive", let event = object["event"] as? [String: Any] { queueProactive(event); return }
        if kind == "revoke", let id = object["id"] as? String {
            proactiveQueue.removeAll { $0["id"] as? String == id }
            if currentEvent?["id"] as? String == id { cancel(); startNextProactive() }
            return
        }
        if kind == "start", let id = object["turn"] as? String {
            if let callID, (object["callId"] as? String != callID || callPaused) { return }
            if object["callId"] != nil && object["callId"] as? String != callID { return }
            for event in proactiveQueue { acknowledge(event, "dropped", "direct_reply") }
            proactiveQueue.removeAll(); cancel(keepWarm:callID != nil)
            guard !password.isEmpty else { callState("failed",turn:id); setStatus("Connect \(serviceName) voice first"); return }
            guard !muted else { callState("failed",turn:id); setStatus("Voice muted"); return }
            turn = id; startedAt = object["startedAt"] as? Double ?? now
            callState("generating",turn:id)
            report = recording ? VoiceSocket.directory.appendingPathComponent("latency-\(UUID().uuidString).jsonl") : nil
            firstPlay = true; onStart?(); setStatus("Waiting for reply")
            record("turn_start")
            return
        }
        guard !turn.isEmpty, object["turn"] as? String == turn else { return }
        switch kind {
        case "sentence":
            guard let text = object["text"] as? String, !text.isEmpty, text.count <= 1500,
                  let index = object["index"] as? Int else { return }
            if pending.count + ready.count > 24 { fail("Reply too long; voice stopped"); return }
            pending.append(Sentence(index: index, text: text, receivedAt: now,
                firstTextAt: object["firstTextAt"] as? Double, sentenceAt: object["sentenceAt"] as? Double))
            record("sentence_ready", ["index": index, "characters": text.count,
                "model_first_text_ms": (object["firstTextAt"] as? Double ?? now) - startedAt,
                "sentence_ms": (object["sentenceAt"] as? Double ?? now) - startedAt])
            synthesizeNext()
        case "end": inputEnded = true; doubaoStream?.finishInput(); finishIfDrained()
        case "cancel": cancel(); setStatus("Voice stopped")
        default: break
        }
    }
    private func synthesizeNext() {
        guard !turn.isEmpty else { return }
        if let event = currentEvent {
            if let reason = proactiveSettings.reason { acknowledge(event,"dropped",reason); cancel(); return }
            if (event["expiresAt"] as? Double ?? 0) <= now { acknowledge(event,"dropped","expired"); cancel(); startNextProactive(); return }
        }
        if provider == .doubao { synthesizeDoubao(); return }
        guard task == nil, streamRequest == nil, !pending.isEmpty, ready.count + streamReady.count < 2 else { return }
        let sentence = pending.removeFirst(), token = generation, began = now
        if streamingSupported { startStreaming(sentence, token:token, began:began); return }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8769/v1/audio/speech")!)
        request.httpMethod = "POST"; request.timeoutInterval = 240
        request.setValue("Bearer " + password, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": "deepseek-web-tts", "input": sentence.text, "voice": "mira", "response_format": "mp3"])
        record("tts_start", ["index": sentence.index, "overlaps_playback": player?.isPlaying == true])
        setStatus(player?.isPlaying == true ? "Speaking · preparing next sentence" : "Mira synthesizing")
        task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.task = nil
                guard error == nil, let data, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    self.fail(code == 401 ? "Reconnect Mira: local password rejected" : "Mira synthesis failed (HTTP \(code)); check service locally")
                    return
                }
                let cached = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-TTS-Cache") == "HIT"
                let clip = Clip(sentence: sentence, data: data, synthesizedAt: self.now, synthesisMS: self.now - began, cached: cached)
                self.ready.append(clip)
                let timings = speechHeaderTimings((response as? HTTPURLResponse)?.value(forHTTPHeaderField:"Server-Timing"))
                self.record("tts_ready", ["index": sentence.index, "tts_ms": clip.synthesisMS, "cache_hit": cached, "bridge_timings":timings])
                self.playNext(); self.synthesizeNext()
            }
        }
        task?.resume()
    }
    private func playNext() {
        guard player == nil, streamPlaying == nil else { return }
        if ready.isEmpty {
            if !streamReady.isEmpty { playStreamNext() }
            return
        }
        if let event = currentEvent {
            if let reason = proactiveSettings.reason { acknowledge(event,"dropped",reason); cancel(); return }
            if (event["expiresAt"] as? Double ?? 0) <= now { acknowledge(event,"dropped","expired"); cancel(); startNextProactive(); return }
        }
        let clip = ready.removeFirst()
        do {
            let next = try AVAudioPlayer(data: clip.data)
            next.delegate = self; next.isMeteringEnabled = true; next.volume = 0.78
            next.prepareToPlay()
            guard next.play() else { fail("Audio playback failed"); return }
            player = next; playing = clip
            let began = now
            record("play_start", ["index": clip.sentence.index, "duration_ms": next.duration * 1000,
                "first_audio": firstPlay, "gap_ms": previousEndedAt.map { max(0, began - $0) } ?? 0,
                "queue_wait_ms": began - clip.synthesizedAt, "tts_ms": clip.synthesisMS, "cache_hit": clip.cached])
            if firstPlay, let event = currentEvent {
                acknowledge(event, "playing")
                onProactivePlayback?(event["kind"] as? String ?? "")
            }
            firstPlay = false
            callState("speaking",turn:turn)
            meter?.invalidate()
            meter = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                guard let self, let player = self.player else { return }
                player.updateMeters()
                let level = min(1, max(0, (Double(player.averagePower(forChannel: 0)) + 48) / 40))
                self.onLevel?(level)
            }
            setStatus("Speaking")
            synthesizeNext()
        } catch { fail("Invalid audio returned by Mira") }
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        record("play_end", ["index": playing?.sentence.index ?? -1, "success": flag])
        previousEndedAt = now
        self.player = nil; playing = nil; meter?.invalidate(); meter = nil; onLevel?(0)
        if !flag { fail("Audio playback interrupted"); return }
        playNext(); synthesizeNext(); finishIfDrained()
        if self.player == nil && (task != nil || !pending.isEmpty) { setStatus("Waiting for next sentence") }
    }
    private func finishIfDrained() {
        if !turn.isEmpty && inputEnded && pending.isEmpty && ready.isEmpty && task == nil && player == nil && streamRequest == nil && (doubaoStream == nil || doubaoAudioEnded) && streamReady.isEmpty && streamPlaying == nil {
            // A completed synthesis session releases playback but can retain its connection.
            if doubaoStream !== warmDoubao { doubaoStream?.cancel() }
            doubaoStream = nil; streamLoading = nil; warmTouched = now
            record("turn_complete")
            callState("finished",turn:turn)
            if let event = currentEvent { acknowledge(event,"finished") }
            currentEvent = nil; turn = ""; setStatus(idleStatus)
            startNextProactive()
        }
    }
    private func fail(_ message: String) {
        let preview = turn.hasPrefix("voice-preview:")
        record("failure", ["message": message])
        callState("failed",turn:turn)
        if let event = currentEvent { acknowledge(event,"failed","synthesis_or_playback_failed"); currentEvent = nil }
        for event in proactiveQueue { acknowledge(event,"failed","voice_unavailable") }
        proactiveQueue.removeAll(); cancel(notifyCall:false); setStatus(message)
        if preview { onTestFailure?(message) }
    }
    func cancel(notifyCall: Bool = true, keepWarm: Bool = false) {
        if let event = currentEvent { acknowledge(event,"cancelled","interrupted"); currentEvent = nil }
        if !turn.isEmpty { record("cancel") }
        if notifyCall && !turn.isEmpty { callState("cancelled",turn:turn) }
        generation = UUID(); task?.cancel(); task = nil
        streamRequest?.cancel(); streamRequest = nil
        if doubaoStream !== warmDoubao || warmDoubao?.reusable != true { doubaoStream?.cancel() }
        doubaoStream = nil
        if !keepWarm { warmDoubao?.cancel(); warmDoubao = nil }
        streamLoading?.audio.stop(); streamLoading = nil
        streamPlaying?.audio.stop(); streamPlaying = nil
        for clip in streamReady { clip.audio.stop() }; streamReady.removeAll()
        pending.removeAll(); ready.removeAll(); player?.stop(); player = nil; playing = nil
        meter?.invalidate(); meter = nil; onLevel?(0)
        turn = ""; inputEnded = false; doubaoAudioEnded = false; previousEndedAt = nil
        setStatus(idleStatus)
    }
    private func startStreaming(_ sentence: Sentence, token: UUID, began: Double) {
        let clip = StreamClip(sentence,makePCMPlayer(),began)
        let stream = SpeechStream()
        streamRequest = stream; streamLoading = clip
        var request = URLRequest(url:URL(string:"http://127.0.0.1:8769/v1/audio/speech")!)
        request.httpMethod = "POST"; request.timeoutInterval = 240
        request.setValue("Bearer " + password,forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject:["model":"deepseek-web-tts","input":sentence.text,"voice":"mira","response_format":"pcm","stream":true])
        record("tts_start",["index":sentence.index,"streaming":true,"overlaps_playback":player != nil || streamPlaying != nil])
        setStatus(streamPlaying == nil ? "\(serviceName) streaming synthesis" : "Speaking · preparing next phrase")
        clip.audio.onStarted = { [weak self, weak clip] in
            guard let self, let clip, self.generation == token else { return }
            self.record("play_start",["index":sentence.index,"streaming":true,"first_audio":self.firstPlay,
                "tts_ms":(clip.firstPacket ?? self.now)-began,"gap_ms":self.previousEndedAt.map { max(0,self.now-$0) } ?? 0,
                "queue_wait_ms":self.now-(clip.firstPacket ?? self.now)])
            if self.firstPlay, let event = self.currentEvent { self.acknowledge(event,"playing"); self.onProactivePlayback?(event["kind"] as? String ?? "") }
            self.firstPlay = false; self.setStatus("Speaking · streaming")
            self.callState("speaking",turn:self.turn)
        }
        clip.audio.onLevel = { [weak self, weak clip] level in
            guard let self, let clip, self.generation == token, self.streamPlaying === clip else { return }; self.onLevel?(level)
        }
        clip.audio.onUnderrun = { [weak self] in if self?.generation == token { self?.record("stream_underrun",["index":sentence.index]) } }
        clip.audio.onFailure = { [weak self] in if self?.generation == token { self?.fail("Audio output did not become ready") } }
        clip.audio.onFinished = { [weak self, weak clip] in
            guard let self, let clip, self.generation == token, self.streamPlaying === clip else { return }
            self.record("play_end",["index":sentence.index,"success":true,"streaming":true])
            self.streamPlaying = nil; self.previousEndedAt = self.now; self.onLevel?(0)
            self.playNext(); self.synthesizeNext(); self.finishIfDrained()
        }
        stream.onAudio = { [weak self, weak clip] data in
            guard let self, let clip, self.generation == token else { return }
            if clip.firstPacket == nil {
                clip.firstPacket = self.now; self.record("tts_first_audio",["index":sentence.index,"streaming":true,"first_packet_ms":self.now-began])
                self.streamReady.append(clip)
            }
            try clip.audio.append(data); self.playNext()
        }
        stream.onEnd = { [weak self, weak clip] frame in
            guard let self, let clip, self.generation == token else { return }
            self.record("tts_ready",["index":sentence.index,"streaming":true,"tts_ms":self.now-began,
                "cache_hit":frame["cached"] as? Bool ?? false,"bridge_timings":speechTimings(frame["timings"])])
            if self.provider == .doubao { self.doubaoVerified = true }
            try clip.audio.finish()
        }
        stream.onComplete = { [weak self] error in
            guard let self, self.generation == token else { return }
            self.streamRequest = nil; self.streamLoading = nil
            if let error { self.fail(self.streamError(error)); return }
            self.playNext(); self.synthesizeNext(); self.finishIfDrained()
        }
        stream.start(request,configuration:session.configuration)
    }
    private func streamError(_ error: Error) -> String {
        guard provider == .doubao else { return "Mira stream failed; check the local service and reconnect" }
        doubaoVerified = false
        if case SpeechStreamError.http(let code) = error {
            if code == 401 || code == 403 {
                password = ""
                return code == 401 ? "Doubao API key rejected (HTTP 401); reconnect with a Speech API Key" : "Doubao voice access denied (HTTP 403); check the Speech API Key and TTS 2.0 service permissions"
            }
            if code == 429 { return "Doubao rate limit reached; try again later" }
            return "Doubao request failed (HTTP \(code)); check the Speech console"
        }
        if case DoubaoSpeechError.rejected(let code) = error { return "Doubao rejected synthesis (\(code)); check voice access and balance" }
        return "Doubao audio stream failed; check your connection and Speech console"
    }
    private func synthesizeDoubao() {
        guard !pending.isEmpty else { return }
        if doubaoStream == nil {
            let first = pending[0], token = generation, began = now
            let clip = StreamClip(first,makePCMPlayer(),began), stream = callID != nil ? prepareDoubao() : makeDoubaoStream()
            doubaoStream = stream; streamLoading = clip
            record("tts_start",["index":first.index,"streaming":true,"transport":"websocket_bidirectional","overlaps_playback":false])
            setStatus("Doubao streaming synthesis")
            clip.audio.onStarted = { [weak self, weak clip] in
                guard let self, let clip, self.generation == token else { return }
                self.record("play_start",["index":first.index,"streaming":true,"first_audio":true,"tts_ms":(clip.firstPacket ?? self.now)-began,"gap_ms":0,"queue_wait_ms":self.now-(clip.firstPacket ?? self.now)])
                if let event = self.currentEvent { self.acknowledge(event,"playing"); self.onProactivePlayback?(event["kind"] as? String ?? "") }
                self.firstPlay = false; self.setStatus("Speaking · streaming")
                self.callState("speaking",turn:self.turn)
            }
            clip.audio.onLevel = { [weak self] level in if self?.generation == token { self?.onLevel?(level) } }
            clip.audio.onUnderrun = { [weak self] in if self?.generation == token { self?.record("stream_underrun",["index":first.index]) } }
            clip.audio.onFailure = { [weak self] in if self?.generation == token { self?.fail("Audio output did not become ready") } }
            clip.audio.onFinished = { [weak self, weak clip] in
                guard let self, let clip, self.generation == token, self.streamPlaying === clip else { return }
                self.record("play_end",["index":first.index,"success":true,"streaming":true]); self.streamPlaying = nil; self.previousEndedAt = self.now; self.onLevel?(0)
                self.finishIfDrained()
            }
            stream.onAudio = { [weak self, weak clip] data in
                guard let self, let clip, self.generation == token else { return }
                if clip.firstPacket == nil {
                    clip.firstPacket = self.now; self.record("tts_first_audio",["index":first.index,"streaming":true,"first_packet_ms":self.now-began]); self.streamReady.append(clip)
                }
                try clip.audio.append(data); self.playNext()
            }
            stream.onEnd = { [weak self, weak clip] frame in
                guard let self, let clip, self.generation == token else { return }
                self.doubaoVerified = true; self.doubaoAudioEnded = true
                self.record("tts_ready",["index":first.index,"streaming":true,"tts_ms":self.now-began,"cache_hit":false,"bridge_timings":speechTimings(frame["timings"])])
                try clip.audio.finish()
            }
            stream.onComplete = { [weak self] error in
                guard let self, self.generation == token else { return }
                self.doubaoStream = nil; self.streamLoading = nil
                if let error { self.fail(self.streamError(error)); return }
                self.finishIfDrained()
            }
            stream.start(key:password,voice:selectedVoice)
        }
        guard let stream = doubaoStream else { return }
        do {
            while !pending.isEmpty {
                let phrase = pending.removeFirst()
                try stream.append(phrase.text)
                record("tts_text_sent",["index":phrase.index,"characters":phrase.text.count])
            }
            if inputEnded { stream.finishInput() }
        } catch { fail("Doubao text stream could not be sent") }
    }
    private func playStreamNext() {
        if let event = currentEvent {
            if let reason = proactiveSettings.reason { acknowledge(event,"dropped",reason); cancel(); return }
            if (event["expiresAt"] as? Double ?? 0) <= now { acknowledge(event,"dropped","expired"); cancel(); startNextProactive(); return }
        }
        let clip = streamReady.removeFirst(); streamPlaying = clip
        do { try clip.audio.play() } catch { fail("Streaming audio playback failed") }
    }
    private func record(_ event: String, _ extra: [String: Any] = [:]) {
        guard let report else { return }
        var value = extra
        value["event"] = event; value["elapsed_ms"] = now - startedAt
        value["provider"] = provider == .doubao ? "doubao" : "mira"
        value["source"] = turn.hasPrefix("voice-preview:") ? "fixed_sample" : "conversation"
        // Reports contain timings and counts only, never credentials or conversation text.
        guard var data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
        data.append(10)
        if !FileManager.default.fileExists(atPath: report.path) {
            FileManager.default.createFile(atPath: report.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        if let file = try? FileHandle(forWritingTo: report) {
            defer { try? file.close() }; _ = try? file.seekToEnd(); try? file.write(contentsOf: data)
        }
    }
}
