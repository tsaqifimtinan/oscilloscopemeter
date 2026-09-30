import Foundation
import os
import Testing
@testable import Scope

private func write(_ ring: SampleRing, _ values: [Float]) {
    values.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: $0.count) }
}

private func latest(_ ring: SampleRing, _ n: Int) -> [Float] {
    [Float](unsafeUninitializedCapacity: n) { buf, count in
        ring.latest(n, into: buf.baseAddress!)
        count = n
    }
}

@Test func partialFillHasLeadingZeros() {
    let ring = SampleRing()
    write(ring, [1, 2, 3])
    #expect(latest(ring, 5) == [0, 0, 1, 2, 3])
}

@Test func wraparoundReturnsExactTail() {
    let ring = SampleRing()
    let total = SampleRing.capacity + 100
    var next = 1
    while next <= total {  // odd chunk size so writes straddle the wrap point
        let end = min(next + 776, total)
        write(ring, (next...end).map(Float.init))
        next = end + 1
    }
    #expect(latest(ring, 1000) == (total - 999...total).map(Float.init))
    #expect(latest(ring, SampleRing.capacity) == (101...total).map(Float.init))
}

@Test func oversizedWriteKeepsTail() {
    let ring = SampleRing()
    let total = SampleRing.capacity + 5
    write(ring, (1...total).map(Float.init))
    #expect(latest(ring, SampleRing.capacity) == (6...total).map(Float.init))
}

@Test func concurrentWriteAndRead() {
    let ring = SampleRing()
    let done = OSAllocatedUnfairLock(initialState: false)
    let total = 2_000_000  // well below 2^24, so every counter value is exact in Float

    DispatchQueue.global(qos: .userInteractive).async {
        let chunk = UnsafeMutablePointer<Float>.allocate(capacity: 480)
        defer { chunk.deallocate() }
        var value = 1
        while value <= total {
            let n = min(480, total - value + 1)
            for i in 0..<n { chunk[i] = Float(value + i) }
            ring.write(chunk, count: n)
            value += n
        }
        done.withLock { $0 = true }
    }

    let n = 4096
    let snap = UnsafeMutablePointer<Float>.allocate(capacity: n)
    defer { snap.deallocate() }
    var reads = 0, torn = 0
    while !done.withLock({ $0 }) || reads == 0 {
        ring.latest(n, into: snap)
        for i in 1..<n where snap[i - 1] != 0 && snap[i] != snap[i - 1] + 1 { torn += 1 }
        reads += 1
    }
    ring.latest(n, into: snap)
    #expect(torn == 0)
    #expect(reads > 0)
    #expect(snap[n - 1] == Float(total))
}
