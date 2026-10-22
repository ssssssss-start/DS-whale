import Foundation

enum Behavior: String, CaseIterable {
    case idle, poke, headpat, greeting, shy, surprised, sad, sleepy
    var isEmotion: Bool { [.shy,.surprised,.sad,.sleepy].contains(self) }
    static let emotions: [Behavior] = [.shy,.surprised,.sad,.sleepy]
    var title: String {
        switch self {
        case .shy: return "Shy"
        case .surprised: return "Surprised"
        case .sad: return "Sad"
        case .sleepy: return "Sleepy"
        default: return rawValue
        }
    }
    var voice: String? {
        switch self {
        case .idle, .shy, .surprised, .sad, .sleepy: return nil
        case .poke: return "poke-hum"
        case .headpat: return "headpat"
        case .greeting: return "welcome"
        }
    }
    var minimumDuration: TimeInterval {
        switch self {
        case .idle: return 0
        case .poke: return 2.4
        case .headpat: return 3.8
        case .greeting: return 8.1
        case .shy, .sad: return 5.2
        case .surprised: return 4.4
        case .sleepy: return 6.0
        }
    }
    var entryDuration: TimeInterval { isEmotion ? 0.75 : self == .poke ? 0.4 : 0.5 }
    var recoveryDuration: TimeInterval { self == .greeting ? 2.2 : isEmotion ? 1.0 : 0.7 }
    var minimumVisibleDuration: TimeInterval {
        switch self {
        case .idle: return 0
        case .poke: return 0.9
        case .headpat: return 2.1
        case .greeting: return 4.0
        case .shy, .surprised, .sad, .sleepy: return 3.0
        }
    }
}

func expressionEase(_ value: Double) -> Double {
    let x = min(1, max(0, value))
    return x * x * (3 - 2 * x)
}

enum BlinkTiming {
    static let duration = 0.28
    static func closure(at elapsed: TimeInterval) -> Double {
        if elapsed < 0 || elapsed >= duration { return 0 }
        if elapsed < 0.08 { return expressionEase(elapsed / 0.08) }
        if elapsed < 0.14 { return 1 }
        return 1 - expressionEase((elapsed - 0.14) / 0.14)
    }
}

final class Interaction {
    private(set) var behavior: Behavior = .idle
    private(set) var started: TimeInterval = 0
    private(set) var ends: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var serial = 0
    private(set) var recoveryStarted: TimeInterval?
    private var recoveryLevel = 0.0
    private var pending: (behavior: Behavior, voiceDuration: TimeInterval)?
    private var lastAccepted: TimeInterval = -.infinity
    func begin(_ next: Behavior, at time: TimeInterval, voiceDuration: TimeInterval = 0) -> Bool {
        guard next != .idle, time - lastAccepted >= 1.1 else { return false }
        lastAccepted = time
        advance(to:time)
        if behavior != .idle {
            pending = (next, voiceDuration)
            recover(at:time)
        } else { start(next, at:time, voiceDuration:voiceDuration) }
        return true
    }
    private func start(_ next: Behavior, at time: TimeInterval, voiceDuration: TimeInterval) {
        behavior = next; started = time
        duration = max(next.minimumDuration, voiceDuration + next.recoveryDuration)
        ends = time + duration; recoveryStarted = nil; serial += 1
    }
    private func recover(at time: TimeInterval) {
        guard behavior != .idle, recoveryStarted == nil else { return }
        let start = max(time, started + behavior.minimumVisibleDuration)
        // A repeated reply must not restart recovery or extend an expression indefinitely.
        guard start < ends - behavior.recoveryDuration else { return }
        recoveryLevel = envelope(at:start)
        recoveryStarted = start
        ends = start + behavior.recoveryDuration
    }
    func interrupt(at time: TimeInterval) { pending = nil; recover(at:time) }
    func advance(to time: TimeInterval) {
        if behavior != .idle && time >= ends {
            behavior = .idle; recoveryStarted = nil
            if let next = pending {
                pending = nil; start(next.behavior, at:time, voiceDuration:next.voiceDuration)
            }
        }
    }
    func reset() { behavior = .idle; pending = nil; recoveryStarted = nil }
    func elapsed(at time: TimeInterval) -> TimeInterval { max(0, time - started) }
    func envelope(at time: TimeInterval) -> Double {
        guard behavior != .idle else { return 0 }
        if let start = recoveryStarted, time >= start {
            return recoveryLevel * (1 - expressionEase((time - start) / (ends - start)))
        }
        let naturalEnd = started + duration
        return min(expressionEase((time - started) / behavior.entryDuration),
                   expressionEase((naturalEnd - time) / behavior.recoveryDuration))
    }
}

func runInteractionChecks() {
    let interaction = Interaction()
    assert(interaction.begin(.poke, at: 10, voiceDuration: 4))
    assert(!interaction.begin(.poke, at: 10.1))
    interaction.advance(to: 13)
    assert(interaction.behavior == .poke, "Reaction must last through its voice clip")
    assert(interaction.begin(.headpat, at: 13.2, voiceDuration: 5))
    assert(interaction.behavior == .poke, "A new interaction waits for the previous recovery")
    interaction.advance(to: 13.91)
    assert(interaction.behavior == .headpat)
    interaction.advance(to: 19.7)
    assert(interaction.behavior == .idle)
    assert(interaction.begin(.greeting, at: 20))
    assert(interaction.envelope(at: 20) == 0)
    assert(interaction.envelope(at: 21) == 1)
    interaction.reset()
    assert(interaction.behavior == .idle)
    let smile = Interaction()
    assert(smile.begin(.headpat, at:0))
    assert(smile.envelope(at:0) == 0 && smile.envelope(at:0.5) == 1)
    assert(smile.envelope(at:3.1) > 0.999 && smile.envelope(at:3.8) < 0.001)
    smile.interrupt(at:0.1)
    assert(smile.recoveryStarted == 2.1 && abs(smile.ends - 2.8) < 0.001)
    assert(smile.envelope(at:1.9) == 1, "A reply preserves a readable smile before recovery")
    let release = smile.ends
    smile.interrupt(at:2.4); smile.interrupt(at:2.5)
    assert(smile.ends == release, "Repeated starts cannot postpone recovery")
    assert(abs(smile.envelope(at:2.1 - 0.0001) - smile.envelope(at:2.1 + 0.0001)) < 0.001)
    let queued = Interaction()
    assert(queued.begin(.headpat, at:0))
    assert(queued.begin(.poke, at:1.2))
    queued.interrupt(at:1.3); queued.advance(to:3)
    assert(queued.behavior == .idle, "Speech removes a pending interaction without replay")
    let latest = Interaction()
    assert(latest.begin(.headpat, at:0))
    assert(latest.begin(.poke, at:1.2))
    assert(latest.begin(.greeting, at:2.4))
    latest.advance(to:2.81)
    assert(latest.behavior == .greeting && latest.serial == 2,"Only the latest pending action starts after recovery")
    assert(BlinkTiming.closure(at:0.1) == 1 && BlinkTiming.closure(at:0.13) == 1)
    assert(BlinkTiming.closure(at:0) == 0 && BlinkTiming.closure(at:0.28) == 0)
    print("Interaction checks passed: eased entry/hold/recovery, readable hold on interruption, latest pending action, no replay, cooldown and blink hold.")
}


func runEmotionChecks() {
    for behavior in Behavior.emotions {
        let state = Interaction()
        assert(state.begin(behavior,at:0))
        assert(behavior.voice == nil, "Emotion preview must not request speech")
        assert(state.envelope(at:0) == 0)
        assert(state.envelope(at:0.75) > 0.99)
        state.interrupt(at:0.8)
        assert(state.envelope(at:2.8) > 0.99, "Keep emotions readable before a speech interruption")
        assert(state.envelope(at:3.5) > 0 && state.envelope(at:3.5) < 1)
        state.advance(to:4.1)
        assert(state.behavior == .idle)
    }
    let state = Interaction()
    assert(state.begin(.shy,at:0))
    assert(state.begin(.sad,at:1.2))
    assert(state.behavior == .shy)
    assert(state.begin(.sleepy,at:2.4))
    state.advance(to:4.1)
    assert(state.behavior == .sleepy, "A new expression waits for recovery and replaces older pending requests")
    print("Emotion timing checks passed: four moods, readable holds, speech recovery, latest pending request, silent previews.")
}
