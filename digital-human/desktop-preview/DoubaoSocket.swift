import Foundation

protocol DoubaoConnection: AnyObject {
    var onOpen: (() -> Void)? { get set }
    var onMessage: ((Data) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
    func open(_ request: URLRequest)
    func send(_ data: Data, completion: @escaping (Error?) -> Void)
    func close()
}

final class DoubaoSocket: NSObject, DoubaoConnection, URLSessionWebSocketDelegate {
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var closed = false
    var onOpen: (() -> Void)?
    var onMessage: ((Data) -> Void)?
    var onError: ((Error) -> Void)?
    func open(_ request: URLRequest) {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        session = URLSession(configuration:config,delegate:self,delegateQueue:.main)
        socket = session!.webSocketTask(with:request); socket?.maximumMessageSize = 2_097_152
        socket?.resume(); receive()
    }
    private func receive() {
        socket?.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self, !self.closed else { return }
                switch result {
                case .success(.data(let data)): self.onMessage?(data); if !self.closed { self.receive() }
                case .success: self.onError?(DoubaoSpeechError.malformed)
                case .failure(let error): self.failed(error)
                }
            }
        }
    }
    func send(_ data: Data, completion: @escaping (Error?) -> Void) {
        guard let socket, !closed else { completion(DoubaoSpeechError.truncated); return }
        socket.send(.data(data)) { error in DispatchQueue.main.async { completion(error) } }
    }
    private func failed(_ error: Error) {
        guard !closed else { return }
        if let response = socket?.response as? HTTPURLResponse, response.statusCode != 101 {
            onError?(SpeechStreamError.http(response.statusCode))
        } else { onError?(error) }
    }
    func close() {
        guard !closed else { return }; closed = true
        socket?.cancel(with:.normalClosure,reason:nil); session?.invalidateAndCancel(); session = nil; socket = nil
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        if !closed { onOpen?() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { failed(error) }
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if !closed { onError?(DoubaoSpeechError.truncated) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

final class DoubaoDuplexStream {
    private enum Phase { case created, opening, connection, idle, session, streaming, finishing, closing, done }
    private var phase = Phase.created
    private let connection: DoubaoConnection
    private var sessionID = ""
    private var retired: [String] = []
    private var sessionRequested = false
    var keepAlive = false
    var reusable: Bool { !sessionRequested && [.created, .opening, .connection, .idle].contains(phase) }
    private var voice = ""
    private var pending: [String] = []
    private var characters = 0
    private var inputEnded = false
    private var packets: [Data] = []
    private var sending = false
    private var audioBytes = 0
    private var timer: Timer?
    private var began = ProcessInfo.processInfo.systemUptime
    private var firstAudio: Double?
    var onAudio: ((Data) throws -> Void)?
    var onEnd: (([String:Any]) throws -> Void)?
    var onComplete: ((Error?) -> Void)?
    init(connection: DoubaoConnection = DoubaoSocket()) { self.connection = connection }
    private var elapsed: Double { (ProcessInfo.processInfo.systemUptime-began)*1000 }
    func start(key: String, voice: String) {
        guard reusable else { onComplete?(DoubaoSpeechError.malformed); return }
        self.voice = voice; sessionID = UUID().uuidString; sessionRequested = true
        characters = 0; inputEnded = false; audioBytes = 0; firstAudio = nil
        began = ProcessInfo.processInfo.systemUptime
        prepare(key:key)
        if phase == .idle { beginSession() }
    }
    func prepare(key: String) {
        guard phase == .created else { return }
        phase = .opening
        var request = URLRequest(url:URL(string:"wss://openspeech.bytedance.com/api/v3/tts/bidirection")!)
        request.timeoutInterval = 90; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(key,forHTTPHeaderField:"X-Api-Key")
        request.setValue("seed-tts-2.0",forHTTPHeaderField:"X-Api-Resource-Id")
        request.setValue(UUID().uuidString,forHTTPHeaderField:"X-Api-Connect-Id")
        connection.onOpen = { [weak self] in
            guard let self, self.phase == .opening else { return }
            self.phase = .connection; self.enqueue(1)
        }
        connection.onMessage = { [weak self] in self?.receive($0) }
        connection.onError = { [weak self] in self?.complete($0) }
        armTimeout(); connection.open(request)
    }
    func append(_ text: String) throws {
        guard !inputEnded, phase != .done, !text.isEmpty, characters + text.count <= 12000 else { throw DoubaoSpeechError.malformed }
        characters += text.count; pending.append(text); armTimeout(); pump()
    }
    func finishInput() { guard !inputEnded, phase != .done else { return }; inputEnded = true; pump() }
    private func pump() {
        guard phase == .streaming else { return }
        while !pending.isEmpty {
            let text = pending.removeFirst()
            enqueue(200,body:["event":200,"req_params":["text":text]])
        }
        if inputEnded { phase = .finishing; enqueue(102) }
    }
    private func enqueue(_ event: Int, body: [String:Any] = [:]) {
        do {
            let id = event >= 100 ? sessionID : ""
            packets.append(try DoubaoPacket.request(event,session:id,body:body)); sendNext()
        } catch { complete(error) }
    }
    private func sendNext() {
        guard !sending, !packets.isEmpty, phase != .done else { return }
        sending = true; let data = packets.removeFirst()
        connection.send(data) { [weak self] error in
            guard let self, self.phase != .done else { return }
            self.sending = false
            if let error { self.complete(error) } else { self.sendNext() }
        }
    }
    private func receive(_ data: Data) {
        guard phase != .done else { return }
        let wasActive = sessionRequested
        do {
            let packet = try DoubaoPacket.decode(data)
            if phase != .idle { armTimeout() }
            if packet.event >= 100 {
                if retired.contains(packet.identifier) { return }
                guard sessionRequested, packet.identifier == sessionID else { throw DoubaoSpeechError.malformed }
            }
            if packet.kind == 11 {
                guard phase == .streaming || phase == .finishing, !packet.payload.isEmpty, packet.payload.count % 2 == 0 else { throw DoubaoSpeechError.malformed }
                firstAudio = firstAudio ?? elapsed; audioBytes += packet.payload.count
                for offset in stride(from:0,to:packet.payload.count,by:9600) {
                    try onAudio?(packet.payload.subdata(in:offset..<min(offset+9600,packet.payload.count)))
                }
                return
            }
            guard let body = try JSONSerialization.jsonObject(with:packet.payload) as? [String:Any] else { throw DoubaoSpeechError.malformed }
            if let code = (body["status_code"] ?? body["code"]) as? Int, code != 0 && code != 20000000 { throw DoubaoSpeechError.rejected(code) }
            switch packet.event {
            case 50:
                guard phase == .connection else { throw DoubaoSpeechError.malformed }
                phase = .idle; timer?.invalidate(); timer = nil
                if sessionRequested { beginSession() }
            case 150:
                guard phase == .session else { throw DoubaoSpeechError.malformed }; phase = .streaming; pump()
            case 152:
                guard phase == .finishing, audioBytes > 0 else { throw DoubaoSpeechError.truncated }
                phase = keepAlive ? .idle : .closing
                timer?.invalidate(); timer = nil
                if keepAlive {
                    retired.append(sessionID); retired = Array(retired.suffix(8)); sessionRequested = false
                }
                try onEnd?(["cached":false,"timings":["first_audio":firstAudio ?? elapsed,"upstream":elapsed,"total":elapsed]])
                if keepAlive { onComplete?(nil) }
                else if phase != .done { armTimeout(); enqueue(2) }
            case 52:
                guard phase == .closing else { throw DoubaoSpeechError.malformed }; complete(nil)
            case 51,151,153: throw DoubaoSpeechError.rejected((body["status_code"] ?? body["code"]) as? Int ?? packet.event)
            case 350,351,354,359,364,154:
                guard phase == .streaming || phase == .finishing else { throw DoubaoSpeechError.malformed }
            default: throw DoubaoSpeechError.malformed
            }
        } catch { complete(error, notify:wasActive || !keepAlive) }
    }
    private func beginSession() {
        phase = .session; armTimeout()
        enqueue(100,body:["event":100,"namespace":"BidirectionalTTS","req_params":["speaker":voice,"audio_params":["format":"pcm","sample_rate":24000]]])
    }
    private func armTimeout() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval:90,repeats:false) { [weak self] _ in self?.complete(DoubaoSpeechError.truncated) }
    }
    private func complete(_ error: Error?, notify explicit: Bool? = nil) {
        guard phase != .done else { return }
        let notify = explicit ?? (sessionRequested || !keepAlive)
        phase = .done
        timer?.invalidate(); timer = nil; pending.removeAll(); packets.removeAll(); connection.close()
        // An idle socket can disappear without failing a reply already playing locally.
        if notify { onComplete?(error) }
    }
    func cancel() {
        guard phase != .done else { return }
        let terminalEvent = phase == .idle ? 2 : phase == .streaming ? 101 : nil
        phase = .done; timer?.invalidate(); timer = nil; pending.removeAll(); packets.removeAll()
        // Cancellation is best effort; close releases the socket even if no acknowledgement arrives.
        if let event = terminalEvent, let data = try? DoubaoPacket.request(event,session:event == 101 ? sessionID : "") {
            connection.send(data) { [connection] _ in connection.close() }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.25) { [connection] in connection.close() }
        } else { connection.close() }
    }
    deinit { timer?.invalidate() }
}
