import os

/// Mono sample history: the capture queue writes, the UI reads the latest N samples.
///
/// Deliberate deviation from the scope doc's lock-free SPSC design: an `OSAllocatedUnfairLock`
/// guards the write position and is held only for one or two memcpys (writer: ~1 K floats,
/// reader: at most 16 K). Tradeoff: the capture queue can briefly wait on a UI read; unfair-lock
/// priority donation limits the inversion. Upgrade path if it ever shows up in profiles:
/// an `Atomic<Int>` write index with a reader that re-checks it after copying.
final class SampleRing: @unchecked Sendable {
    static let capacity = 65_536  // power of two; indices wrap with a mask
    private static let mask = capacity - 1

    private let storage: UnsafeMutablePointer<Float>
    private let written = OSAllocatedUnfairLock(initialState: 0)  // total samples ever written

    init() {
        storage = .allocate(capacity: Self.capacity)
        storage.initialize(repeating: 0, count: Self.capacity)
    }

    deinit { storage.deallocate() }

    /// Appends samples. Allocation-free; if `count` exceeds capacity only the tail is kept.
    func write(_ src: UnsafePointer<Float>, count: Int) {
        let n = min(count, Self.capacity)
        let src = src + (count - n)
        // withLockUnchecked: withLock wants a @Sendable body, and raw pointers aren't Sendable.
        written.withLockUnchecked { total in
            let start = (total + count - n) & Self.mask  // skip the dropped head
            let first = min(n, Self.capacity - start)
            (storage + start).update(from: src, count: first)
            storage.update(from: src + first, count: n - first)
            total += count
        }
    }

    /// Copies the most recent `n` samples into `dst`, oldest first. Zeros precede the first write.
    func latest(_ n: Int, into dst: UnsafeMutablePointer<Float>) {
        precondition(n <= Self.capacity)
        written.withLockUnchecked { total in
            let start = (total - n) & Self.mask
            let first = min(n, Self.capacity - start)
            dst.update(from: storage + start, count: first)
            (dst + first).update(from: storage, count: n - first)
        }
    }
}
