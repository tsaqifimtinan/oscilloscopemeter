import Accelerate
import os

struct MeterSnapshot: Sendable {
    var rmsL: Float = -120  // dBFS
    var rmsR: Float = -120
    /// VU readings in dBFS (RMS-equivalent); the UI subtracts the reference to get VU.
    var vuL: Float = -120
    var vuR: Float = -120
    var vuMono: Float = -120  // (L+R)/2
    /// Loudness (LUFS / LU); nil until enough audio has been measured.
    var momentary: Double?
    var shortTerm: Double?
    var integrated: Double?
    var loudnessRange: Double?
    /// Max since the last loudness reset, dBFS / dBTP.
    var samplePeak: Float = -120
    var truePeak: Float = -120
    var loudnessHeld = false
    var overruns = 0
}

/// Consumes every sample from `feed` on its own queue and publishes meter readings.
/// The UI pulls `snapshot`.
final class MeterEngine: @unchecked Sendable {  // mutable state is touched only on `queue` (tests call drain() directly)
    private static let chunk = 4_096
    private static let rmsWindow = 4_800  // 100 ms @ 48 kHz
    private static let silenceAfterNs: UInt64 = 300_000_000
    private static let sampleRate = 48_000.0
    private static let tickSamples = 480  // 10 ms

    private let feed: StereoFeed
    private let queue = DispatchQueue(label: "scope.meters", qos: .userInitiated)
    private let published = OSAllocatedUnfairLock(initialState: MeterSnapshot())
    private let commands = OSAllocatedUnfairLock(initialState: (reset: false, hold: false))
    private let l = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
    private let r = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
    private let mono = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
    private let zeros = UnsafeMutablePointer<Float>.allocate(capacity: tickSamples)

    private var timer: DispatchSourceTimer?
    private var cursor = 0
    private var current = MeterSnapshot()
    private var lastSampleNs: UInt64 = 0
    // Plain 100 ms RMS for the small dBFS text readout.
    private var sumL: Float = 0, sumR: Float = 0, count = 0
    private var vuL = VUBallistics(sampleRate: sampleRate)
    private var vuR = VUBallistics(sampleRate: sampleRate)
    private var vuMono = VUBallistics(sampleRate: sampleRate)
    private var loudness = LoudnessMeter()
    private var truePeakL = TruePeak(), truePeakR = TruePeak()
    private var samplePeak: Float = 0, truePeak: Float = 0  // linear, since last reset

    init(feed: StereoFeed) {
        self.feed = feed
        zeros.initialize(repeating: 0, count: Self.tickSamples)
    }

    deinit {
        l.deallocate()
        r.deallocate()
        mono.deallocate()
        zeros.deallocate()
    }

    var snapshot: MeterSnapshot { published.withLock { $0 } }

    /// Clears integrated, LRA, momentary/short-term history, K-filter state and max peaks.
    func resetLoudness() {
        commands.withLock { $0.reset = true }
    }

    /// Hold: integrated and LRA stop accumulating and freeze; M and S keep moving.
    func setLoudnessHeld(_ held: Bool) {
        commands.withLock { $0.hold = held }
    }

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
            vuL = VUBallistics(sampleRate: Self.sampleRate)
            vuR = VUBallistics(sampleRate: Self.sampleRate)
            vuMono = VUBallistics(sampleRate: Self.sampleRate)
            // Loudness readings survive stop/start; only Reset clears them.
            (current.rmsL, current.rmsR) = (-120, -120)
            (current.vuL, current.vuR, current.vuMono) = (-120, -120, -120)
            published.withLock { $0 = current }
        }
    }

    /// Reads everything new from the feed and publishes the result.
    func drain() {
        let now = DispatchTime.now().uptimeNanoseconds
        let command = commands.withLock { c in
            defer { c.reset = false }
            return c
        }
        if command.reset {
            loudness.reset()
            truePeakL.reset()
            truePeakR.reset()
            (samplePeak, truePeak) = (0, 0)
        }
        loudness.held = command.hold
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
            var half: Float = 0.5
            vDSP_vasm(l, 1, r, 1, &half, mono, 1, vDSP_Length(n))
            updateVU(l: l, r: r, mono: mono, count: n)
            loudness.process(l: l, r: r, count: n)
            var peakL: Float = 0, peakR: Float = 0
            vDSP_maxmgv(l, 1, &peakL, vDSP_Length(n))
            vDSP_maxmgv(r, 1, &peakR, vDSP_Length(n))
            samplePeak = max(samplePeak, peakL, peakR)
            truePeak = max(truePeak, truePeakL.process(l, count: n), truePeakR.process(r, count: n))
            if count >= Self.rmsWindow {
                current.rmsL = dBFS(rms: (sumL / Float(count)).squareRoot())
                current.rmsR = dBFS(rms: (sumR / Float(count)).squareRoot())
                (sumL, sumR, count) = (0, 0, 0)
            }
        }
        if now &- lastSampleNs > Self.silenceAfterNs {
            current.rmsL = -120
            current.rmsR = -120
            // No audio arriving: let the needles fall naturally instead of freezing.
            updateVU(l: zeros, r: zeros, mono: zeros, count: Self.tickSamples)
        }
        current.momentary = loudness.momentary
        current.shortTerm = loudness.shortTerm
        current.integrated = loudness.integrated
        current.loudnessRange = loudness.loudnessRange
        current.samplePeak = 20 * log10(max(samplePeak, 1e-6))
        current.truePeak = 20 * log10(max(truePeak, 1e-6))
        current.loudnessHeld = command.hold
        published.withLock { $0 = current }
    }

    private func updateVU(l: UnsafePointer<Float>, r: UnsafePointer<Float>, mono: UnsafePointer<Float>, count n: Int) {
        current.vuL = vuL.process(UnsafeBufferPointer(start: l, count: n), refRMS: 1)
        current.vuR = vuR.process(UnsafeBufferPointer(start: r, count: n), refRMS: 1)
        current.vuMono = vuMono.process(UnsafeBufferPointer(start: mono, count: n), refRMS: 1)
    }
}
