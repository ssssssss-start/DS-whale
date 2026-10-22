import AppKit

final class ProactiveSettings {
    private let defaults: UserDefaults
    private(set) var revision: Double
    private(set) var dndUntil: Double
    var proactive: Bool { didSet { changed() } }
    var companion: Bool { didSet { changed() } }
    var quietStart: Int { didSet { changed() } }
    var quietEnd: Int { didSet { changed() } }
    var muted = false { didSet { changed() } }
    var visible = true { didSet { changed() } }
    var active = true { didSet { changed() } }
    private(set) var lastInteraction: Double
    var onChange: (() -> Void)?
    var now: () -> Double = { Date().timeIntervalSince1970 * 1000 }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        revision = defaults.double(forKey: "proactiveRevision")
        dndUntil = defaults.double(forKey: "dndUntil")
        proactive = defaults.bool(forKey: "proactiveVoice")
        companion = defaults.bool(forKey: "companionCheckIns")
        quietStart = defaults.object(forKey: "quietStart") as? Int ?? 1380
        quietEnd = defaults.object(forKey: "quietEnd") as? Int ?? 540
        lastInteraction = defaults.double(forKey: "whaleLastInteraction")
    }
    var dnd: Bool { dndUntil == -1 || dndUntil > now() }
    var quiet: Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = Date(timeIntervalSince1970: now() / 1000)
        let value = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return quietStart == quietEnd ? false : quietStart < quietEnd ? value >= quietStart && value < quietEnd : value >= quietStart || value < quietEnd
    }
    var reason: String? {
        if !proactive { return "proactive_off" }
        if muted { return "muted" }
        if !visible { return "hidden" }
        if !active { return "device_inactive" }
        if dnd { return "dnd" }
        if quiet { return "quiet_hours" }
        return nil
    }
    var dndTitle: String {
        if !dnd { return "Do Not Disturb: Off" }
        if dndUntil == -1 { return "Do Not Disturb: Until Turned Off" }
        let formatter = DateFormatter(); formatter.timeStyle = .short
        return "Do Not Disturb: Until " + formatter.string(from: Date(timeIntervalSince1970: dndUntil / 1000))
    }
    func setDND(minutes: Int?) {
        dndUntil = minutes.map { $0 > 0 ? now() + Double($0) * 60_000 : 0 } ?? -1
        changed()
    }
    func interact() { lastInteraction = now(); changed() }
    func expire() {
        if dndUntil > 0 && dndUntil <= now() { dndUntil = 0; changed() }
    }
    private func changed() {
        revision = max(revision + 1, now())
        defaults.set(revision, forKey: "proactiveRevision")
        defaults.set(dndUntil, forKey: "dndUntil")
        defaults.set(proactive, forKey: "proactiveVoice")
        defaults.set(companion, forKey: "companionCheckIns")
        defaults.set(quietStart, forKey: "quietStart"); defaults.set(quietEnd, forKey: "quietEnd")
        defaults.set(lastInteraction, forKey: "whaleLastInteraction")
        onChange?()
    }
    func snapshot(playing: Bool) -> [String: Any] {
        ["type":"desktop_state", "revision": revision, "dndUntil":dndUntil, "proactive":proactive,
         "companion":companion, "quietStart":quietStart, "quietEnd":quietEnd,
         "timeZone": TimeZone.current.identifier, "muted":muted, "visible":visible, "active":active,
         "lastInteraction":lastInteraction, "playing":playing]
    }
}

func runProactiveSettingsChecks() {
    let suite = "whale-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = ProactiveSettings(defaults: defaults)
    var time = 1_000_000.0
    settings.now = { time }; settings.proactive = true; settings.quietStart = 0; settings.quietEnd = 0
    settings.setDND(minutes: 30)
    assert(settings.dnd && settings.reason == "dnd")
    let restored = ProactiveSettings(defaults: defaults); restored.now = { time }
    assert(restored.dnd, "DND must survive restart")
    time += 30 * 60_000; restored.expire(); assert(!restored.dnd)
    restored.setDND(minutes: nil); assert(restored.dnd)
    restored.setDND(minutes: 0); assert(restored.reason == nil)
    restored.muted = true; restored.setDND(minutes: 0)
    assert(restored.reason == "muted", "DND off must not unmute audio")
    restored.muted = false; restored.visible = false; assert(restored.reason == "hidden")
    restored.visible = true; restored.active = false; assert(restored.reason == "device_inactive")
    print("Proactive settings checks passed: expiry, restart, independent mute/visibility and inactivity gates.")
}
