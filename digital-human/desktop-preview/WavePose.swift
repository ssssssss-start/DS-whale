import Foundation

struct WavePose {
    let from: Int
    let to: Int
    let blend: Double
    private static let segments: [(from: Int, to: Int, time: Double)] = [
        (0,0,0.2), (0,1,1.6), (1,1,0.2), (1,2,0.8), (2,2,0.8),
        (2,3,0.45), (3,3,0.35), (3,2,0.45), (2,2,0.35), (2,3,0.45),
        (3,4,0.5), (4,4,0.2), (4,1,0.4), (1,0,1.25), (0,0,0.1)
    ]

    static func at(_ elapsed: TimeInterval, duration: TimeInterval) -> WavePose {
        guard duration > 0, elapsed > 0, elapsed < duration else { return WavePose(from: 0, to: 0, blend: 0) }
        let phase = elapsed / duration * segments.reduce(0) { $0 + $1.time }
        var start = 0.0
        for segment in segments {
            if phase < start + segment.time {
                return WavePose(from:segment.from, to:segment.to, blend:expressionEase((phase - start) / segment.time))
            }
            start += segment.time
        }
        return WavePose(from: 0, to: 0, blend: 0)
    }
}

struct WaveRecovery {
    private struct Segment {
        let from: Int, to: Int
        let begin: Double, end: Double
        var distance: Double { abs(end - begin) }
    }
    private let segments: [Segment]
    private static let paths = [[0], [1,0], [2,1,0], [3,4,1,0], [4,1,0]]
    init(from pose: WavePose) {
        let a = Self.paths[pose.from], b = Self.paths[pose.to]
        let returnViaFrom = pose.blend + Double(a.count - 1) <= 1 - pose.blend + Double(b.count - 1)
        let path = returnViaFrom ? a : b
        let endpoint = returnViaFrom ? 0.0 : 1.0
        var result: [Segment] = []
        if pose.from != pose.to, abs(pose.blend - endpoint) > 0.000001 {
            result.append(Segment(from:pose.from, to:pose.to, begin:pose.blend, end:endpoint))
        }
        for pair in zip(path, path.dropFirst()) {
            result.append(Segment(from:pair.0, to:pair.1, begin:0, end:1))
        }
        segments = result
    }
    func at(_ progress: Double) -> WavePose {
        let distance = segments.reduce(0) { $0 + $1.distance }
        var remaining = min(1, max(0, progress)) * distance
        for segment in segments {
            if remaining < segment.distance {
                let blend = segment.begin + (segment.end - segment.begin) * expressionEase(remaining / segment.distance)
                return WavePose(from:segment.from, to:segment.to, blend:blend)
            }
            remaining -= segment.distance
        }
        return WavePose(from:0, to:0, blend:0)
    }
}

func runWaveChecks() {
    for duration in [2.0, 3.3, 5.0] {
        assert(WavePose.at(0, duration: duration).from == 0)
        assert(WavePose.at(duration, duration: duration).to == 0)
        var previous = 0.0
        for tick in 0...1000 {
            let pose = WavePose.at(duration * Double(tick) / 1000, duration: duration)
            assert((0...4).contains(pose.from) && (0...4).contains(pose.to))
            assert((0...1).contains(pose.blend))
            let position = Double(pose.from) * (1 - pose.blend) + Double(pose.to) * pose.blend
            assert(abs(position - previous) < 0.1, "Continuous progress at every keyframe boundary")
            previous = position
        }
    }
    let held = WavePose.at(3.2, duration:8.1)
    assert(held.from == 2 && held.to == 2, "The smiling raised-hand pose has a readable hold")
    let earlyLift = WavePose.at(0.7,duration:8.1), lateLift = WavePose.at(1.6,duration:8.1)
    assert(earlyLift.from == 0 && earlyLift.to == 1 && earlyLift.blend < 0.3)
    assert(lateLift.from == 0 && lateLift.to == 1 && lateLift.blend < 1,"The initial lift cannot finish in a fraction of a second")
    for (a,b) in [(0,1),(1,2),(2,3),(3,2),(3,4),(4,1),(1,0),(2,2)] {
        for blend in [0.0,0.2,0.5,0.9,1.0] {
            let pose = WavePose(from:a,to:b,blend:blend)
            let recovery = WaveRecovery(from:pose)
            let first = recovery.at(0)
            func position(_ p: WavePose) -> Double { Double(p.from) * (1-p.blend) + Double(p.to) * p.blend }
            assert(abs(position(first) - position(pose)) < 0.001,"Recovery starts at the currently displayed pose")
            var previous = position(first)
            for tick in 1...1000 {
                let next = position(recovery.at(Double(tick) / 1000))
                assert(abs(next - previous) < 0.03,"Return follows available full-body transitions without jumps")
                previous = next
            }
            assert(previous == 0)
        }
    }
    print("Wave checks passed: key-pose holds, continuous transitions, interrupted return from partial/held poses, source bounds and rest endpoints.")
}
