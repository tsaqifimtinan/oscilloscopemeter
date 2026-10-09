import Accelerate
import os

enum SpectrogramChannel: String, Codable, CaseIterable, Sendable {
    // Mix and Mid are the same math; both are listed because both names are in the menu.
    case mix = "Mix", left = "L", right = "R", mid = "Mid", side = "Side"
}

enum FrequencyRange: String, Codable, CaseIterable, Sendable {
    case full = "20 Hz – 20 kHz", music = "30 Hz – 16 kHz", low = "20 Hz – 5 kHz"

    var bounds: (min: Double, max: Double) {
        switch self {
        case .full: (20, 20_000)
        case .music: (30, 16_000)
        case .low: (20, 5_000)
        }
    }
}

/// Everything that shapes the history; any change clears it.
struct SpectrogramConfig: Equatable, Sendable {
    static let fftSizes = [2048, 4096, 8192]
    var fftSize = 4096
    var history = 10.0  // seconds across the view
    var channel = SpectrogramChannel.mix
    var range = FrequencyRange.full
    var columns = 1024  // texture width
    var rows = 512

    /// Samples between columns, so `columns` columns span `history` seconds.
    var hop: Int { max(128, Int((SpectrogramEngine.sampleRate * history / Double(columns)).rounded())) }
}

/// Ring of finished columns (UInt8 per row). One producer (the engine), one consumer (the renderer),
/// same cursor model as StereoFeed plus a generation so the reader notices clears.
final class ColumnQueue: @unchecked Sendable {
    struct Cursor {
        var position = 0
        var generation = 0
    }

    let rows: Int
    let capacity: Int
    private let data: UnsafeMutablePointer<UInt8>
    private let state = OSAllocatedUnfairLock(initialState: Cursor())  // columns written since the last clear

    init(rows: Int, capacity: Int = 256) {
        self.rows = rows
        self.capacity = capacity
        data = .allocate(capacity: rows * capacity)
        data.initialize(repeating: 0, count: rows * capacity)
    }

    deinit { data.deallocate() }

    func push(_ column: UnsafePointer<UInt8>) {
        state.withLockUnchecked { s in
            (data + (s.position % capacity) * rows).update(from: column, count: rows)
            s.position += 1
        }
    }

    func clear() {
        state.withLock { s in
            s.position = 0
            s.generation += 1
        }
    }

    /// Up to `max` columns since `cursor`, oldest first, `rows` bytes each; advances `cursor`.
    /// `cleared` means the history was reset since the last read: the reader should wipe its copy.
    func read(cursor: inout Cursor, into out: UnsafeMutablePointer<UInt8>, max: Int)
        -> (count: Int, overrun: Bool, cleared: Bool) {
        state.withLockUnchecked { s in
            let cleared = cursor.generation != s.generation
            if cleared { cursor = Cursor(position: 0, generation: s.generation) }
            let overrun = s.position - cursor.position > capacity
            if overrun { cursor.position = s.position - capacity }
            let n = min(s.position - cursor.position, max)
            for i in 0..<n {
                (out + i * rows).update(from: data + ((cursor.position + i) % capacity) * rows, count: rows)
            }
            cursor.position += n
            return (n, overrun, cleared)
        }
    }
}

struct SpectrumSnapshot: Sendable {
    /// Loudest bin of the newest column (debug readout).
    var peakHz: Float = 0
    var peakDB: Float = -120
    var columns = 0  // since the last clear
    var overruns = 0
}

/// Consumes every sample from `feed` on its own queue, runs an FFT every `hop` samples and pushes
/// one quantized column per FFT into `columns`. Mutable state is touched only on `queue`
/// (tests call drain() directly).
final class SpectrogramEngine: @unchecked Sendable {
    static let sampleRate = 48_000.0
    private static let chunk = 4_096
    private static let maxFFT = SpectrogramConfig.fftSizes.max()!

    let columns: ColumnQueue
    /// Test hook: sees each FFT input frame (oldest sample first). Nil in the app.
    var onFrame: ((UnsafePointer<Float>) -> Void)?

    private let feed: StereoFeed
    private let queue = DispatchQueue(label: "scope.spectrogram", qos: .userInitiated)
    private let published = OSAllocatedUnfairLock(initialState: SpectrumSnapshot())
    private let commands = OSAllocatedUnfairLock(initialState: Commands())
    private let l = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
    private let r = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
    private let mixed = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
    private let sliding = UnsafeMutablePointer<Float>.allocate(capacity: maxFFT)  // circular, fftSize used
    private let frame = UnsafeMutablePointer<Float>.allocate(capacity: maxFFT)
    private let db = UnsafeMutablePointer<Float>.allocate(capacity: maxFFT / 2)
    private let column: UnsafeMutablePointer<UInt8>

    private var config: SpectrogramConfig
    private var analyzer: SpectrumAnalyzer
    private var map: RowMap
    private var timer: DispatchSourceTimer?
    private var cursor: Int
    private var slidingPos = 0  // next write index = oldest sample
    private var untilColumn = 0
    private var current = SpectrumSnapshot()
    private var paused = false

    private struct Commands {
        var config: SpectrogramConfig?
        var clear = false
        var active = true
    }

    init(feed: StereoFeed, config: SpectrogramConfig = .init()) {
        self.feed = feed
        self.config = config
        columns = ColumnQueue(rows: config.rows)
        column = .allocate(capacity: config.rows)
        analyzer = SpectrumAnalyzer(fftSize: config.fftSize)
        map = Self.rowMap(config)
        cursor = feed.position()
        restart()
    }

    deinit {
        for p in [l, r, mixed, sliding, frame, db] { p.deallocate() }
        column.deallocate()
    }

    var snapshot: SpectrumSnapshot { published.withLock { $0 } }

    /// Applied on the next drain; clears the history. Rows can't change after init.
    func configure(_ config: SpectrogramConfig) {
        precondition(config.rows == columns.rows && SpectrogramConfig.fftSizes.contains(config.fftSize))
        commands.withLock { $0.config = config }
    }

    /// Clears the history (key C).
    func clear() {
        commands.withLock { $0.clear = true }
    }

    /// While inactive (panel hidden) samples are skipped without any FFT work; showing again
    /// resyncs and starts a fresh history.
    func setActive(_ active: Bool) {
        commands.withLock { $0.active = active }
    }

    func start() {
        queue.async { [self] in
            cursor = feed.position()
            restart()  // don't glue old audio to new
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
        }
    }

    /// Reads everything new from the feed and pushes any finished columns.
    func drain() {
        let command = commands.withLock { c in
            defer { (c.config, c.clear) = (nil, false) }
            return c
        }
        guard command.active else {
            cursor = feed.position()
            paused = true
            return
        }
        if let next = command.config, next != config {
            if next.fftSize != config.fftSize { analyzer = SpectrumAnalyzer(fftSize: next.fftSize) }
            config = next
            map = Self.rowMap(next)
            cursor = feed.position()
            restart()
        } else if command.clear || paused {
            restart()
        }
        paused = false
        while true {
            let (n, overrun) = feed.read(cursor: &cursor, l: l, r: r, max: Self.chunk)
            if overrun { current.overruns += 1 }
            guard n > 0 else { break }
            consume(selectChannel(count: n), count: n)
        }
        published.withLock { $0 = current }
    }

    private static func rowMap(_ c: SpectrogramConfig) -> RowMap {
        RowMap(fftSize: c.fftSize, fMin: c.range.bounds.min, fMax: c.range.bounds.max, rows: c.rows,
               sampleRate: sampleRate)
    }

    private func restart() {
        sliding.update(repeating: 0, count: config.fftSize)
        slidingPos = 0
        untilColumn = config.fftSize  // first column once a full window has arrived
        columns.clear()
        current.columns = 0
        (current.peakHz, current.peakDB) = (0, -120)
    }

    private func selectChannel(count n: Int) -> UnsafePointer<Float> {
        var half: Float = 0.5
        switch config.channel {
        case .left: return UnsafePointer(l)
        case .right: return UnsafePointer(r)
        case .mix, .mid: vDSP_vasm(l, 1, r, 1, &half, mixed, 1, vDSP_Length(n))
        case .side: vDSP_vsbsm(l, 1, r, 1, &half, mixed, 1, vDSP_Length(n))
        }
        return UnsafePointer(mixed)
    }

    /// Appends samples to the sliding window, emitting a column every time `untilColumn` hits 0.
    private func consume(_ src: UnsafePointer<Float>, count: Int) {
        let size = config.fftSize
        var done = 0
        while done < count {
            let k = min(count - done, untilColumn, size - slidingPos)
            (sliding + slidingPos).update(from: src + done, count: k)
            slidingPos = (slidingPos + k) % size
            untilColumn -= k
            done += k
            if untilColumn == 0 {
                emitColumn()
                untilColumn = config.hop
            }
        }
    }

    private func emitColumn() {
        let size = config.fftSize
        frame.update(from: sliding + slidingPos, count: size - slidingPos)
        (frame + size - slidingPos).update(from: sliding, count: slidingPos)
        onFrame?(frame)
        analyzer.process(frame, dbOut: db)
        var peak: Float = 0
        var bin: vDSP_Length = 0
        vDSP_maxvi(db + 1, 1, &peak, &bin, vDSP_Length(size / 2 - 1))
        current.peakDB = peak
        current.peakHz = Float(Double(bin + 1) * Self.sampleRate / Double(size))
        map.apply(db: db, into: column)
        columns.push(column)
        current.columns += 1
    }
}
