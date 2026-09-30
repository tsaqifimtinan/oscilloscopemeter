import Accelerate
import os

struct MeterSnapshot: Sendable {
    var rmsL: Float = -120  // dBFS
    var rmsR: Float = -120
    var overruns = 0
}

/// Consumes every sample from `feed` on its own queue and publishes meter readings.
/// The UI pulls `snapshot`; VU and loudness plug into `drain()` (M9, M10).
final class MeterEngine: @unchecked Sendable {  // mutable state is touched only on `queue` (tests call drain() directly)
    private static let chunk = 4_096
    private static let rmsWindow = 4_800  // 100 ms @ 48 kHz
    private static let silenceAfterNs: UInt64 = 300_000_000

    private let feed: StereoFeed
    private let queue = DispatchQueue(label: "scope.meters", qos: .userInitiated)
    private let published = OSAllocatedUnfairLock(initialState: MeterSnapshot())
    private let l = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
    private let r = UnsafeMutablePointer<Float>.allocate(capacity: chunk)

    private var timer: DispatchSourceTimer?
    private var cursor = 0
    private var current = MeterSnapshot()
    private var lastSampleNs: UInt64 = 0
    // ponytail: plain 100 ms RMS for the readout; VU/LUFS replace it in M9/M10.
    private var sumL: Float = 0, sumR: Float = 0, count = 0

    init(feed: StereoFeed) {
        self.feed = feed
    }

    deinit {
        l.deallocate()
        r.deallocate()
    }

    var snapshot: MeterSnapshot { published.withLock { $0 } }

    func start() {
        queue.async { [self] in
            cursor = feed.position()
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
            t.setEventHandler { [unowned self] in drain() }
            t.resume()
            timer = t
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            (sumL, sumR, count) = (0, 0, 0)
            current = MeterSnapshot()
            published.withLock { $0 = current }
        }
    }

    /// Reads everything new from the feed and publishes the result.
    func drain() {
        let now = DispatchTime.now().uptimeNanoseconds
        while true {
            let (n, overrun) = feed.read(cursor: &cursor, l: l, r: r, max: Self.chunk)
            if overrun { current.overruns += 1 }
            guard n > 0 else { break }
            lastSampleNs = now
            var sl: Float = 0, sr: Float = 0
            vDSP_svesq(l, 1, &sl, vDSP_Length(n))
            vDSP_svesq(r, 1, &sr, vDSP_Length(n))
            sumL += sl
            sumR += sr
            count += n
            if count >= Self.rmsWindow {
                current.rmsL = dBFS(rms: (sumL / Float(count)).squareRoot())
                current.rmsR = dBFS(rms: (sumR / Float(count)).squareRoot())
                (sumL, sumR, count) = (0, 0, 0)
            }
        }
        if now &- lastSampleNs > Self.silenceAfterNs {
            current.rmsL = -120
            current.rmsR = -120
        }
        published.withLock { $0 = current }
    }
}
