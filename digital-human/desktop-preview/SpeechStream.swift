import Foundation

enum SpeechStreamError: Error { case invalidFrame, truncated, unavailable, http(Int) }

protocol SpeechFrames: AnyObject {
    var audio: ((Data) throws -> Void)? { get set }
    var end: (([String:Any]) throws -> Void)? { get set }
    func append(_ data: Data) throws
    func finish() throws
}

final class PCMFrames: SpeechFrames {
    private var pending = Data()
    private var sequence = 0
    private var metadata = false
    private(set) var ended = false
    var audio: ((Data) throws -> Void)?
    var end: (([String:Any]) throws -> Void)?
    func append(_ data: Data) throws {
        for offset in stride(from:0,to:data.count,by:16384) {
            let start = data.index(data.startIndex,offsetBy:offset)
            let end = data.index(data.startIndex,offsetBy:min(offset+16384,data.count))
            pending.append(data[start..<end])
            try parseAvailable()
            guard pending.count <= 131072 else { throw SpeechStreamError.invalidFrame }
        }
    }
    private func parseAvailable() throws {
        while let newline = pending.firstIndex(of:10) {
            let line = pending.prefix(upTo:newline); pending.removeSubrange(...newline)
            guard line.count <= 131072, !ended,
                  let frame = try JSONSerialization.jsonObject(with:line) as? [String:Any] else { throw SpeechStreamError.invalidFrame }
            switch frame["type"] as? String {
            case "meta":
                guard !metadata, frame["sample_rate"] as? Int == 24000, frame["channels"] as? Int == 1,
                      frame["format"] as? String == "pcm_s16le" else { throw SpeechStreamError.invalidFrame }
                metadata = true
            case "audio":
                guard metadata, frame["seq"] as? Int == sequence, let raw = frame["pcm"] as? String,
                      let data = Data(base64Encoded:raw), !data.isEmpty, data.count <= 9600, data.count % 2 == 0 else { throw SpeechStreamError.invalidFrame }
                sequence += 1; try audio?(data)
            case "end":
                guard metadata, sequence > 0 else { throw SpeechStreamError.invalidFrame }
                ended = true; try end?(frame)
            default: throw SpeechStreamError.invalidFrame
            }
        }
    }
    func finish() throws {
        guard ended, pending.isEmpty else { throw SpeechStreamError.truncated }
    }
}

final class SpeechStream: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private let frames: SpeechFrames
    private let localHeader: Bool
    private var completed = false
    var onAudio: ((Data) throws -> Void)?
    var onEnd: (([String:Any]) throws -> Void)?
    var onComplete: ((Error?) -> Void)?
    init(frames: SpeechFrames = PCMFrames(), localHeader: Bool = true) {
        self.frames = frames; self.localHeader = localHeader; super.init()
    }
    func start(_ request: URLRequest, configuration: URLSessionConfiguration) {
        frames.audio = { [weak self] in try self?.onAudio?($0) }
        frames.end = { [weak self] in try self?.onEnd?($0) }
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        session = URLSession(configuration:configuration,delegate:self,delegateQueue:.main)
        task = session!.dataTask(with:request); task?.resume()
    }
    func cancel() {
        completed = true; task?.cancel(); session?.invalidateAndCancel(); session = nil
    }
    private func complete(_ error: Error?) {
        guard !completed else { return }
        completed = true; task?.cancel(); session?.invalidateAndCancel(); session = nil
        onComplete?(error)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else {
            completionHandler(.cancel); complete(SpeechStreamError.unavailable); return
        }
        guard response.statusCode == 200 else { completionHandler(.cancel); complete(SpeechStreamError.http(response.statusCode)); return }
        guard !localHeader || response.value(forHTTPHeaderField:"X-Whale-Stream") == "pcm-v1" else {
            completionHandler(.cancel); complete(SpeechStreamError.unavailable); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Speech credentials are valid only for the configured endpoint.
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !completed else { return }
        do { try frames.append(data) } catch { complete(error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !completed else { return }
        if let error { complete(error); return }
        do { try frames.finish(); complete(nil) } catch { complete(error) }
    }
}

func speechTimings(_ value: Any?) -> [String:Double] {
    guard let input = value as? [String:Any], input.count <= 32 else { return [:] }
    let allowed = Set(["lock_wait","create_session","pow","copy","verify","voice","upstream","encode","restore","cleanup","first_audio","upstream_first_packet","total"])
    return input.reduce(into:[:]) { result, pair in
        if allowed.contains(pair.key), let number = pair.value as? Double, number.isFinite, number >= 0 { result[pair.key] = number }
    }
}

func speechHeaderTimings(_ value: String?) -> [String:Double] {
    var result: [String:Double] = [:]
    for part in (value ?? "").split(separator:",") {
        let pieces = part.trimmingCharacters(in:.whitespaces).components(separatedBy:";dur=")
        if pieces.count == 2, let duration = Double(pieces[1]) { result[pieces[0]] = duration }
    }
    return speechTimings(result)
}
