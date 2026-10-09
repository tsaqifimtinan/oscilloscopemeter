import Accelerate
import Foundation

/// Maps FFT bins onto `rows` log-spaced frequency rows (row 0 = fMin) with a spectral tilt,
/// and quantizes to UInt8 (0…255 = -120…0 dBFS). Built once per setting; `apply` doesn't allocate.
struct RowMap {
    let rows: Int
    let fMin: Double, fMax: Double
    /// Rows below this span less than one bin and interpolate between `lo` and `lo + 1`;
    /// rows from here up take the max over `lo...hi`, so narrow tones aren't averaged away.
    private(set) var firstMaxRow: Int
    private(set) var lo: [Int]
    private(set) var hi: [Int]
    private(set) var frac: [Float]
    private(set) var tilt: [Float]

    init(fftSize n: Int, fMin: Double, fMax: Double, rows: Int, sampleRate: Double, tiltDBPerOct: Double) {
        self.rows = rows
        self.fMin = fMin
        self.fMax = fMax
        lo = .init(repeating: 0, count: rows)
        hi = lo
        frac = .init(repeating: 0, count: rows)
        tilt = frac
        firstMaxRow = rows
        let lastBin = n / 2 - 1  // bin 0 is DC/Nyquist; skip it
        let binPerHz = Double(n) / sampleRate
        for r in 0..<rows {
            let lower = Self.frequency(row: Double(r), fMin: fMin, fMax: fMax, rows: rows) * binPerHz
            let upper = Self.frequency(row: Double(r + 1), fMin: fMin, fMax: fMax, rows: rows) * binPerHz
            let center = Self.frequency(row: Double(r) + 0.5, fMin: fMin, fMax: fMax, rows: rows)
            tilt[r] = Float(tiltDBPerOct * log2(center / 1000))
            if upper - lower < 1 && firstMaxRow == rows {
                let pos = center * binPerHz
                let base = min(max(Int(pos), 1), lastBin - 1)
                lo[r] = base
                hi[r] = base + 1
                frac[r] = Float(min(max(pos - Double(base), 0), 1))
            } else {
                // Span ≥ 1 bin, so ceil(lower)…floor(upper) holds at least one bin.
                if firstMaxRow == rows { firstMaxRow = r }
                lo[r] = min(max(Int(lower.rounded(.up)), 1), lastBin)
                hi[r] = min(max(Int(upper), lo[r]), lastBin)
            }
        }
    }

    /// Frequency at a fractional row position; row + 0.5 is a row's center.
    static func frequency(row: Double, fMin: Double, fMax: Double, rows: Int) -> Double {
        fMin * pow(fMax / fMin, row / Double(rows))
    }

    /// Fractional row index whose center is `f` (labels use this so they can't drift from the data).
    func row(for f: Double) -> Double {
        Double(rows) * log(f / fMin) / log(fMax / fMin) - 0.5
    }

    func apply(db: UnsafePointer<Float>, into out: UnsafeMutablePointer<UInt8>) {
        for r in 0..<rows {
            var v: Float = 0
            if r < firstMaxRow {
                let a = db[lo[r]]
                v = a + frac[r] * (db[hi[r]] - a)
            } else {
                vDSP_maxv(db + lo[r], 1, &v, vDSP_Length(hi[r] - lo[r] + 1))
            }
            let q = ((v + tilt[r] + 120) / 120 * 255).rounded()
            out[r] = q.isNaN ? 0 : UInt8(min(max(q, 0), 255))
        }
    }
}
