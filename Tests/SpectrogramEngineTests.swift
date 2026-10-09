import Foundation
import Testing
@testable import Scope

private func write(_ feed: StereoFeed, _ l: [Float], _ r: [Float]? = nil) {
    let r = r ?? l
    l.withUnsafeBufferPointer { lp in
        r.withUnsafeBufferPointer { rp in feed.write(l: lp.baseAddress!, r: rp.baseAddress!, count: l.count) }
    }
}

private func readColumns(_ engine: SpectrogramEngine, _ cursor: inout ColumnQueue.Cursor) -> [[UInt8]] {
    let rows = engine.columns.rows
    var out = [UInt8](repeating: 0, count: rows * 256)
    let (n, overrun, _) = engine.columns.read(cursor: &cursor, into: &out, max: 256)
    #expect(!overrun)
    return (0..<n).map { Array(out[$0 * rows..<($0 + 1) * rows]) }
}

@Test func hopCountingSkipsAndDuplicatesNothing() {
    let feed = StereoFeed()
    var config = SpectrogramConfig()
    config.channel = .left
    let engine = SpectrogramEngine(feed: feed, config: config)
    let n = config.fftSize, hop = config.hop
    #expect(hop == 469)
    var starts: [Float] = []
    var contiguous = true
    engine.onFrame = { frame in
        starts.append(frame[0])
        for i in 1..<n where frame[i] != frame[0] + Float(i) { contiguous = false }
    }
    let total = 50_000
    var next = 0
    for size in [1, 7, 4096, 333, 10_000, 469, 468, 470] + Array(repeating: 1_000, count: 40) where next < total {
        let k = min(size, total - next)
        write(feed, (next..<next + k).map(Float.init))
        next += k
        engine.drain()
    }
    #expect(next == total)
    #expect(starts.count == (total - n) / hop + 1)
    #expect(starts == (0..<starts.count).map { Float($0 * hop) })
    #expect(contiguous)
    #expect(engine.snapshot.columns == starts.count)
    #expect(engine.snapshot.overruns == 0)
}

@Test func debugPeakReadsOneKilohertz() {
    let feed = StereoFeed()
    let engine = SpectrogramEngine(feed: feed)
    let tone = sine(1000, amplitude: 0.5, count: 9600)
    write(feed, tone)  // Mix of identical L and R = the tone itself
    engine.drain()
    let s = engine.snapshot
    #expect(abs(s.peakHz - 1000) <= 48_000 / 4096)
    #expect(abs(s.peakDB + 6) < 2)  // off-bin, so up to ~1.4 dB scallop loss below -6
}

@Test func sideChannelCancelsIdenticalChannels() {
    let feed = StereoFeed()
    var config = SpectrogramConfig()
    config.channel = .side
    let engine = SpectrogramEngine(feed: feed, config: config)
    var cursor = ColumnQueue.Cursor()
    write(feed, sine(1000, count: 9600))
    engine.drain()
    let columns = readColumns(engine, &cursor)
    #expect(!columns.isEmpty)
    #expect(columns.allSatisfy { $0.allSatisfy { $0 == 0 } })
}

@Test func longSilenceStaysAtZero() {
    let feed = StereoFeed()
    let engine = SpectrogramEngine(feed: feed)
    var cursor = ColumnQueue.Cursor()
    let zeros = [Float](repeating: 0, count: 4_800)
    var count = 0
    for _ in 0..<600 {  // 60 s
        write(feed, zeros)
        engine.drain()
        for column in readColumns(engine, &cursor) {
            #expect(column.allSatisfy { $0 == 0 })
            count += 1
        }
    }
    #expect(count == (60 * 48_000 - 4096) / 469 + 1)
    #expect(engine.snapshot.peakDB.isFinite)
}

@Test func logChirpPeakRowRises() {
    let feed = StereoFeed()
    let engine = SpectrogramEngine(feed: feed)
    var cursor = ColumnQueue.Cursor()
    // 20 Hz → 20 kHz exponential chirp over 10 s.
    let seconds = 10.0, sr = 48_000.0, k = log(1000.0)
    let total = Int(seconds * sr)
    var peaks: [Double] = []
    for start in stride(from: 0, to: total, by: 4_800) {
        write(feed, (start..<start + 4_800).map { i in
            let t = Double(i) / sr
            return Float(sin(2 * .pi * 20 * seconds / k * (exp(k * t / seconds) - 1)))
        })
        engine.drain()
        peaks += readColumns(engine, &cursor).map(plateauCenter)
    }
    // Below ~860 Hz rows are narrower than a bin and interpolate linearly in dB, so the max is a
    // plateau of tied rows (the middle is taken) that leans toward the flatter neighbouring bin as
    // the tone nears a bin center: the peak can slip back by a fraction of a bin. Strict
    // monotonicity (PLAN-4) is impossible with that interpolation; allow ≤ 2 rows (< 1 bin above 20 Hz).
    let worst = zip(peaks, peaks.dropFirst()).map { $0 - $1 }.max()!
    #expect(worst <= 2, "peak row fell back \(worst) rows")
    #expect(peaks.indices.dropFirst(100).allSatisfy { peaks[$0] > peaks[$0 - 100] })  // rises over every ~1 s
    #expect(peaks.first! < 40 && peaks.last! > 480)
}

private func plateauCenter(_ column: [UInt8]) -> Double {
    let top = column.max()!
    return Double(column.firstIndex(of: top)! + column.lastIndex(of: top)!) / 2
}

@Test func reconfiguringFiftyTimesKeepsRunning() {
    let feed = StereoFeed()
    let engine = SpectrogramEngine(feed: feed)
    var cursor = ColumnQueue.Cursor()
    var start = 0
    for i in 0..<50 {
        var config = SpectrogramConfig()
        config.fftSize = SpectrogramConfig.fftSizes[i % 3]
        config.channel = SpectrogramChannel.allCases[i % 5]
        config.range = FrequencyRange.allCases[i % 3]
        config.history = [5, 10, 20, 30][i % 4]
        engine.configure(config)
        engine.drain()
        #expect(engine.snapshot.columns == 0)  // history cleared
        let left = sine(440, count: 10_000, start: start), right = sine(3000, count: 10_000, start: start)
        start += 10_000
        write(feed, left, right)
        engine.drain()
        let columns = readColumns(engine, &cursor)
        #expect(columns.count == (10_000 - config.fftSize) / config.hop + 1)
        #expect(engine.snapshot.peakDB.isFinite)
    }
}

@Test func hiddenEngineSkipsWorkAndRestartsFresh() {
    let feed = StereoFeed()
    let engine = SpectrogramEngine(feed: feed)
    var frames = 0
    engine.onFrame = { _ in frames += 1 }
    engine.setActive(false)
    write(feed, sine(1000, count: 20_000))
    engine.drain()
    #expect(frames == 0)
    engine.setActive(true)
    write(feed, sine(1000, count: 4_096))
    engine.drain()
    #expect(frames == 1)  // only post-show audio, from a fresh window
    #expect(engine.snapshot.columns == 1)
    engine.clear()
    engine.drain()
    #expect(engine.snapshot.columns == 0)
}
