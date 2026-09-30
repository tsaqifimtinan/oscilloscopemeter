import os

/// Stereo sample history with one producer (the capture queue) and any number of consumers.
/// The scope takes snapshots with `latest(n)`; meters use `read(cursor:)`, which returns every
/// sample exactly once, in order, as long as the consumer keeps up.
///
/// Deliberate deviation from the scope doc's lock-free SPSC design: an `OSAllocatedUnfairLock`
/// guards the write position and is held only for memcpys (at most two per plane). Tradeoff: the
/// capture queue can briefly wait on a reader; unfair-lock priority donation limits the inversion.
/// Upgrade path if it ever shows up in profiles: an `Atomic<Int>` write index with readers that
/// re-check it after copying.
final class StereoFeed: @unchecked Sendable {
    let capacity: Int
    private let mask: Int
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>
    private let written = OSAllocatedUnfairLock(initialState: 0)  // total samples ever written

    init(capacityPow2: Int = 1 << 17) {  // ~2.7 s @ 48 kHz
        precondition(capacityPow2 > 0 && capacityPow2 & (capacityPow2 - 1) == 0)
        capacity = capacityPow2
        mask = capacityPow2 - 1
        left = .allocate(capacity: capacityPow2)
        right = .allocate(capacity: capacityPow2)
        left.initialize(repeating: 0, count: capacityPow2)
        right.initialize(repeating: 0, count: capacityPow2)
    }

    deinit {
        left.deallocate()
        right.deallocate()
    }

    /// Producer only. Allocation-free; if `count` exceeds capacity only the tail is kept.
    func write(l: UnsafePointer<Float>, r: UnsafePointer<Float>, count: Int) {
        let n = min(count, capacity)
        let skip = count - n
        // withLockUnchecked: withLock wants a @Sendable body, and raw pointers aren't Sendable.
        written.withLockUnchecked { total in
            let start = (total + skip) & mask
            store(l + skip, into: left, at: start, count: n)
            store(r + skip, into: right, at: start, count: n)
            total += count
        }
    }

    /// Total samples written so far; a new consumer starts its cursor here.
    func position() -> Int {
        written.withLock { $0 }
    }

    /// Newest `n` samples, oldest first. Zeros precede the first write.
    func latest(_ n: Int, l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>) {
        precondition(n <= capacity)
        written.withLockUnchecked { total in
            let start = (total - n) & mask
            load(left, at: start, count: n, into: l)
            load(right, at: start, count: n, into: r)
        }
    }

    /// Up to `max` samples written since `cursor`, in order; advances `cursor`.
    /// If the consumer fell more than `capacity` behind, it skips to the oldest sample still held
    /// and reports `overrun`.
    func read(cursor: inout Int, l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>,
              max: Int) -> (count: Int, overrun: Bool) {
        written.withLockUnchecked { total in
            let overrun = total - cursor > capacity
            if overrun { cursor = total - capacity }
            let n = min(total - cursor, max)
            load(left, at: cursor & mask, count: n, into: l)
            load(right, at: cursor & mask, count: n, into: r)
            cursor += n
            return (n, overrun)
        }
    }

    private func store(_ src: UnsafePointer<Float>, into plane: UnsafeMutablePointer<Float>, at start: Int, count n: Int) {
        let first = min(n, capacity - start)
        (plane + start).update(from: src, count: first)
        plane.update(from: src + first, count: n - first)
    }

    private func load(_ plane: UnsafeMutablePointer<Float>, at start: Int, count n: Int, into dst: UnsafeMutablePointer<Float>) {
        let first = min(n, capacity - start)
        dst.update(from: plane + start, count: first)
        (dst + first).update(from: plane, count: n - first)
    }
}
