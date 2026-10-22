import Foundation
import Darwin

func runVoiceConfigChecks() {
    let fm = FileManager.default
    let folder = fm.temporaryDirectory.appendingPathComponent("whale-config-check-" + UUID().uuidString)
    try! fm.createDirectory(at:folder, withIntermediateDirectories:false, attributes:[.posixPermissions:0o700])
    defer { try? fm.removeItem(at:folder) }
    let url = folder.appendingPathComponent("voice-config.local.json")
    func write(_ text: String) { try! Data(text.utf8).write(to:url) }
    func rejects(_ text: String) {
        write(text)
        do { _ = try VoiceConfig.load(from:url); assertionFailure("Invalid config must fail") }
        catch let error as VoiceConfigError { assert(!error.message.contains("mock-key")) }
        catch { assertionFailure("Only sanitized errors are exposed") }
    }
    assert(try! VoiceConfig.load(from:url) == nil)
    write("{\"doubao_api_key\":\"\"}")
    assert(try! VoiceConfig.load(from:url) == nil)
    write("{\"doubao_api_key\":\"  mock-key  \"}")
    chmod(url.path, 0o644)
    assert(try! VoiceConfig.load(from:url) == "mock-key")
    let mode = try! fm.attributesOfItem(atPath:url.path)[.posixPermissions] as! NSNumber
    assert(mode.intValue & 0o777 == 0o600)
    rejects("{\"doubao_api_key\":\"mock-key\"")
    rejects("{}")
    rejects("{\"doubao_api_key\":123}")
    rejects("{\"doubao_api_key\":\"mock-key\\nsecond-line\"}")
    rejects("{\"doubao_api_key\":\"mock-key\\u0000\"}")
    rejects(String(repeating:"x", count:16_385))
    let target = folder.appendingPathComponent("target.json")
    try! fm.moveItem(at:url, to:target)
    try! fm.createSymbolicLink(at:url, withDestinationURL:target)
    do { _ = try VoiceConfig.load(from:url); assertionFailure("Symlink must fail") } catch {}
    try! fm.removeItem(at:url)
    try! fm.createDirectory(at:url, withIntermediateDirectories:false)
    do { _ = try VoiceConfig.load(from:url); assertionFailure("Directory must fail") } catch {}
    print("Voice config checks passed: missing/empty, whitespace, schema, sanitized errors, file size/type, symlink refusal and owner-only permissions (mock files only).")
}
