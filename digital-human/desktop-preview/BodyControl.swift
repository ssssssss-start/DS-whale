import Foundation

final class BodyControl {
    var perform: ((Behavior) -> String)?
    var available: () -> Bool = { false }
    var now: () -> Double = { Date().timeIntervalSince1970 * 1000 }
    private var receipts: [(String, [String:Any])] = []
    var actions: [String] { perform == nil ? [] : Behavior.allCases.map(\.rawValue) }

    func receive(_ object: [String:Any]) -> [String:Any]? {
        guard object["type"] as? String == "body_action",
              let id = object["id"] as? String, UUID(uuidString:id) != nil,
              let action = object["action"] as? String else { return nil }
        // Retransmission acknowledges the original command without replaying a movement.
        if let previous = receipts.first(where: { $0.0 == id }) { return previous.1 }
        let status: String
        if let deadline = object["expiresAt"] as? Double, deadline.isFinite, deadline > now(), deadline <= now() + 5000 {
            if let behavior = Behavior(rawValue:action) {
                status = available() ? perform?(behavior) ?? "unavailable" : "unavailable"
            } else { status = "unsupported" }
        } else { status = "expired" }
        let result: [String:Any] = ["type":"body_result", "id":id, "action":action, "status":status]
        receipts.append((id,result))
        if receipts.count > 128 { receipts.removeFirst() }
        return result
    }
}

func runBodyControlChecks() {
    let body = BodyControl()
    var movements: [Behavior] = []
    body.now = { 1000 }; body.available = { true }
    body.perform = { movements.append($0); return "accepted" }
    func command(_ action: String, deadline: Double = 2000) -> [String:Any] {
        ["type":"body_action", "id":UUID().uuidString, "action":action, "expiresAt":deadline]
    }
    for behavior in Behavior.allCases {
        let request = command(behavior.rawValue)
        assert(body.receive(request)?["status"] as? String == "accepted")
        assert(body.receive(request)?["status"] as? String == "accepted")
    }
    assert(movements == Behavior.allCases, "Every supported action executes once, including idle")
    assert(body.receive(command("fly"))?["status"] as? String == "unsupported")
    assert(body.receive(command("greeting",deadline:999))?["status"] as? String == "expired")
    assert(body.receive(command("greeting",deadline:9000))?["status"] as? String == "expired")
    body.available = { false }
    assert(body.receive(command("greeting"))?["status"] as? String == "unavailable")
    body.available = { true }; body.perform = { _ in "busy" }
    assert(body.receive(command("headpat"))?["status"] as? String == "busy")
    assert(movements.count == Behavior.allCases.count)
    print("Body control checks passed: supported actions, receipts, dedupe, expiry, hidden/inactive gate and busy state (mock scene).")
}
