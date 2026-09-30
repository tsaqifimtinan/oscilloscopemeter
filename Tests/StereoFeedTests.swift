import Foundation
import os
import Testing
@testable import Scope

// Ramps: L = 1, 2, 3…; R = −L, so channel mix-ups show.
private func ramp(_ range: ClosedRange<Int>) -> (l: [Float], r: [Float]) {
    (range.map(Float.init), range.map { -Float($0) })
}

private func write(_ feed: StereoFeed, _ range: ClosedRange<Int>) {
    let (l, r) = ramp(range)
    l.withUnsafeBufferPointer { lp in
        r.withUnsafeBufferPointer { rp in feed.write(l: lp.baseAddress!, r: rp.baseAddress!, count: l.count) }
    }
}

private func latest(_ feed: StereoFeed, _ n: Int) -> (l: [Float], r: [Float]) {
    var l = [Float](repeating: .nan, count: n), r = l
    feed.latest(n, l: &l, r: &r)
    return (l, r)
}

private func read(_ feed: StereoFeed, _ cursor: inout Int, max: Int) -> (l: [Float], r: [Float], overrun: Bool) {
    var l = [Float](repeating: .nan, count: max), r = l
    let (n, overrun) = feed.read(cursor: &cursor, l: &l, r: &r, max: max)
    return (Array(l[..<n]), Array(r[..<n]), overrun)
}

/// Reads until empty in steps of `max`.
private func readAll(_ feed: StereoFeed, _ cursor: inout Int, max: Int) -> (l: [Float], r: [Float]) {
    var l: [Float] = [], r: [Float] = []
    while true {
        let chunk = read(feed, &cursor, max: max)
        #expect(!chunk.overrun)
        if chunk.l.isEmpty { return (l, r) }
        l += chunk.l
        r += chunk.r
    }
}

@Test func latestPartialFillHasLeadingZeros() {
    let feed = StereoFeed(capacityPow2: 1024)
    write(feed, 1...3)
    let (l, r) = latest(feed, 5)
    #expect(l == [0, 0, 1, 2, 3])
    #expect(r == [0, 0, -1, -2, -3])
}

@Test func latestAcrossWraparound() {
    let feed = StereoFeed(capacityPow2: 1024)
    var next = 1
    while next <= 1124 {  // odd chunk size so writes straddle the wrap point
        let end = min(next + 76, 1124)
        write(feed, next...end)
        next = end + 1
    }
    #expect(latest(feed, 1000) == ramp(125...1124))
    #expect(latest(feed, 1024) == ramp(101...1124))
}

@Test func oversizedWriteKeepsTail() {
    let feed = StereoFeed(capacityPow2: 1024)
    write(feed, 1...1029)
    #expect(latest(feed, 1024) == ramp(6...1029))
}

@Test func readPreservesOrderAcrossWraparound() {
    let feed = StereoFeed(capacityPow2: 1024)
    var cursor = feed.position()
    var got: (l: [Float], r: [Float]) = ([], [])
    var next = 1
    while next <= 5000 {
        let end = min(next + 332, 5000)
        write(feed, next...end)
        next = end + 1
        let chunk = readAll(feed, &cursor, max: 200)
        got.l += chunk.l
        got.r += chunk.r
    }
    #expect(got == ramp(1...5000))
}

@Test func consumersHaveIndependentCursors() {
    let feed = StereoFeed(capacityPow2: 1024)
    var a = 0, b = 0
    write(feed, 1...600)
    #expect(readAll(feed, &a, max: 50) == ramp(1...600))
    write(feed, 601...900)
    #expect(readAll(feed, &b, max: 1024) == ramp(1...900))
    #expect(readAll(feed, &a, max: 7) == ramp(601...900))
    #expect(readAll(feed, &b, max: 1024).l.isEmpty)
}

@Test func overrunSkipsToOldestAndReportsOnce() {
    let feed = StereoFeed(capacityPow2: 1024)
    var cursor = 0
    write(feed, 1...2048)
    let first = read(feed, &cursor, max: 4096)
    #expect(first.overrun)
    #expect(first.l == ramp(1025...2048).l)
    write(feed, 2049...2058)
    let second = read(feed, &cursor, max: 4096)
    #expect(!second.overrun)
    #expect((second.l, second.r) == ramp(2049...2058))
}

/// Producer writes a ramp at ~10× realtime while a consumer reads every ~1 ms: every sample must
/// arrive exactly once, in order. Duration from STRESS_SECONDS (default 2); run the 60 s acceptance
/// with `TEST_RUNNER_STRESS_SECONDS=60 ./scripts/build.sh test`.
@Test(.timeLimit(.minutes(3))) func producerConsumerRampStress() {
    let seconds = Double(ProcessInfo.processInfo.environment["STRESS_SECONDS"] ?? "") ?? 2
    let feed = StereoFeed()
    let chunks = Int(seconds * 1000)
    let done = OSAllocatedUnfairLock(initialState: false)
    let wrap = 1 << 24  // keep ramp values exact in Float

    Thread.detachNewThread {
        let l = UnsafeMutablePointer<Float>.allocate(capacity: 480)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: 480)
        defer { l.deallocate(); r.deallocate() }
        var value = 0
        for _ in 0..<chunks {
            for i in 0..<480 {
                l[i] = Float((value + i) % wrap)
                r[i] = -l[i]
            }
            feed.write(l: l, r: r, count: 480)
            value += 480
            Thread.sleep(forTimeInterval: 0.001)
        }
        done.withLock { $0 = true }
    }

    let max = 4096
    let l = UnsafeMutablePointer<Float>.allocate(capacity: max)
    let r = UnsafeMutablePointer<Float>.allocate(capacity: max)
    defer { l.deallocate(); r.deallocate() }
    var cursor = 0, expected = 0, mismatches = 0, overruns = 0
    while true {
        let finished = done.withLock { $0 }
        let (n, overrun) = feed.read(cursor: &cursor, l: l, r: r, max: max)
        if overrun { overruns += 1 }
        for i in 0..<n {
            let want = Float((expected + i) % wrap)
            if l[i] != want || r[i] != -want { mismatches += 1 }
        }
        expected += n
        if finished && n == 0 { break }
        if n < max { Thread.sleep(forTimeInterval: 0.001) }
    }
    #expect(overruns == 0)
    #expect(mismatches == 0)
    #expect(expected == chunks * 480)
}

@Test func meterEngineMeasuresRMS() {
    let feed = StereoFeed()
    let l = [Float](repeating: 0.5, count: 9600)
    let r = [Float](repeating: 0.25, count: 9600)
    feed.write(l: l, r: r, count: 9600)
    let engine = MeterEngine(feed: feed)
    engine.drain()
    let m = engine.snapshot
    #expect(abs(m.rmsL - -6.0206) < 0.001)
    #expect(abs(m.rmsR - -12.0412) < 0.001)
    #expect(m.overruns == 0)
}
