import Foundation
import Darwin

enum VoiceConfigError: Error {
    case unreadable, invalid
    var message: String {
        switch self {
        case .unreadable: return "Cannot read voice-config.local.json. Use a regular file owned by your account, smaller than 16 KB."
        case .invalid: return "Invalid voice config. Use a JSON object with a doubao_api_key string containing a single-line Speech API Key."
        }
    }
}

enum VoiceConfig {
    static var url: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("voice-config.local.json")
    }
    private struct Values: Decodable { let doubao_api_key: String }
    static func load(from url: URL) throws -> String? {
        // Open the same file we validate; never follow a credential-file symlink.
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw VoiceConfigError.unreadable
        }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_size <= 16_384,
              fchmod(fd, 0o600) == 0 else { throw VoiceConfigError.unreadable }
        var data = Data(), buffer = [UInt8](repeating:0, count:4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw VoiceConfigError.unreadable
            }
            guard data.count + count <= 16_384 else { throw VoiceConfigError.unreadable }
            data.append(contentsOf:buffer.prefix(count))
        }
        guard let values = try? JSONDecoder().decode(Values.self, from:data) else { throw VoiceConfigError.invalid }
        let key = values.doubao_api_key.trimmingCharacters(in:.whitespacesAndNewlines)
        guard key.utf8.count <= 8192, !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw VoiceConfigError.invalid
        }
        return key.isEmpty ? nil : key
    }
}
