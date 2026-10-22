import Foundation

enum VoiceProvider { case doubao, mira }
enum DoubaoSpeechError: Error { case rejected(Int), malformed, truncated }
struct DoubaoVoice {
    let id: String
    let title: String
    static let choices = [
        DoubaoVoice(id:"zh_female_tianmeixiaoyuan_uranus_bigtts",title:"Sweet Xiaoyuan 2.0"),
        DoubaoVoice(id:"zh_female_sajiaoxuemei_uranus_bigtts",title:"Playful Xuemei 2.0"),
        DoubaoVoice(id:"zh_female_wenrouxiaoya_uranus_bigtts",title:"Gentle Xiaoya 2.0"),
        DoubaoVoice(id:"zh_female_vv_uranus_bigtts",title:"Vivi 2.0"),
        DoubaoVoice(id:"zh_female_xiaohe_uranus_bigtts",title:"Xiaohe 2.0"),
        DoubaoVoice(id:"zh_male_m191_uranus_bigtts",title:"Yunzhou 2.0"),
        DoubaoVoice(id:"zh_male_taocheng_uranus_bigtts",title:"Xiaotian 2.0")
    ]
    static let defaultID = choices[0].id
}

struct DoubaoPacket {
    let kind: Int
    let event: Int
    let identifier: String
    let payload: Data
    private static let connectionEvents = Set([1,2,50,51,52])
    static func request(_ event: Int, session: String = "", body: [String:Any] = [:]) throws -> Data {
        var data = Data([0x11,0x14,0x10,0])
        put(UInt32(event),into:&data)
        if !connectionEvents.contains(event) {
            guard !session.isEmpty else { throw DoubaoSpeechError.malformed }
            let id = Data(session.utf8); put(UInt32(id.count),into:&data); data.append(id)
        }
        let json = try JSONSerialization.data(withJSONObject:body)
        put(UInt32(json.count),into:&data); data.append(json); return data
    }
    static func put(_ value: UInt32, into data: inout Data) {
        var big = value.bigEndian; withUnsafeBytes(of:&big) { data.append(contentsOf:$0) }
    }
    static func decode(_ data: Data) throws -> DoubaoPacket {
        guard data.count >= 8, data.count <= 2_097_152 else { throw DoubaoSpeechError.malformed }
        let bytes = Array(data); let kind = Int(bytes[1] >> 4); let flags = bytes[1] & 15
        let serialization = bytes[2] >> 4
        let header = Int(bytes[0] & 15) * 4
        guard bytes[0] >> 4 == 1, header >= 4, header <= data.count, bytes[2] & 15 == 0,
              serialization == 0 || serialization == 1 else { throw DoubaoSpeechError.malformed }
        var cursor = header
        func number() throws -> Int {
            guard cursor + 4 <= bytes.count else { throw DoubaoSpeechError.malformed }
            let result = bytes[cursor..<cursor+4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            cursor += 4; return Int(result)
        }
        func block() throws -> Data {
            let size = try number(); guard cursor + size <= bytes.count else { throw DoubaoSpeechError.malformed }
            let result = Data(bytes[cursor..<cursor+size]); cursor += size; return result
        }
        if kind == 15 {
            let code = try number(); _ = try block()
            guard cursor == bytes.count else { throw DoubaoSpeechError.malformed }
            throw DoubaoSpeechError.rejected(code)
        }
        guard (kind == 9 || kind == 11), flags == 4 else { throw DoubaoSpeechError.malformed }
        let event = try number()
        let identifierData = try block()
        guard let identifier = String(data:identifierData,encoding:.utf8) else { throw DoubaoSpeechError.malformed }
        let payload = try block()
        guard cursor == bytes.count, kind != 11 || (event == 352 && serialization == 0) else { throw DoubaoSpeechError.malformed }
        return DoubaoPacket(kind:kind,event:event,identifier:identifier,payload:payload)
    }
}
