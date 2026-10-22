import Foundation
import Darwin

func runVoiceSocketChecks() {
    let folder = URL(fileURLWithPath:"/tmp/whale-ipc-test-\(UUID().uuidString)",isDirectory:true)
    defer { try? FileManager.default.removeItem(at:folder) }
    for round in 0..<2 {
        let server = VoiceSocket(folder:folder)
        do { try server.start { object in if object["type"] as? String == "ping" { server.send(["type":"pong"]) } } }
        catch { fatalError("Isolated socket start failed: \(error)") }
        let fd = socket(AF_UNIX,SOCK_STREAM,0)
        var address = sockaddr_un();address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(folder.appendingPathComponent("speech.sock").path.utf8CString)
        withUnsafeMutableBytes(of:&address.sun_path) { $0.copyBytes(from:path.map { UInt8(bitPattern:$0) }) }
        let result = withUnsafePointer(to:&address) { pointer in pointer.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        assert(result == 0,"Connection must work after app restart with existing directory")
        let data = Data("{\"type\":\"ping\"}\n".utf8)
        data.withUnsafeBytes { _ = Darwin.write(fd,$0.baseAddress!,data.count) }
        var received = false
        DispatchQueue.global().async {
            var buffer=[UInt8](repeating:0,count:1024)
            var timeout=timeval(tv_sec:2,tv_usec:0)
            setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
            let count=Darwin.read(fd,&buffer,buffer.count)
            let good=count>0 && String(bytes:buffer.prefix(max(0,count)),encoding:.utf8)?.contains("pong")==true
            DispatchQueue.main.async { received=good }
        }
        let limit=Date(timeIntervalSinceNow:3)
        while !received && Date()<limit { RunLoop.current.run(until:Date(timeIntervalSinceNow:0.01)) }
        close(fd);server.stop()
        assert(received,"Round \(round): bidirectional IPC must complete")
    }
    print("Socket integration passed: fresh start, bidirectional JSON and restart with existing directory.")
}
