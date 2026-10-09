import Accelerate
import Foundation

/// Maps FFT bins onto `rows` log-spaced frequency rows (row 0 = fMin) and quantizes to UInt8 (0…255 = -120…0 dBFS). Built once per setting; `apply` doesn't allocate.
struct RowMap {
    let rows: Int
    let fMin: Double, fMax: Double
    /// Rows below this span less than one bin and interpolate between `lo` and `lo + 1`;
    /// rows from here up take the max over `lo...hi`, so narrow tones aren't averaged away.
    private(set) var firstMaxRow: Int
    private(set) var lo: [Int]
    private(set) var hi: [Int]
    private(set) var frac: [Float]

    init(fftSize n: Int, fMin: Double, fMax: Double, rows: Int, sampleRate: Double) {
        self.rows = rows
        self.fMin = fMin
        self.fMax = fMax
        lo = .init(repeating: 0, count: rows)
        hi = lo
        frac = .init(repeating: 0, count: rows)
        firstMaxRow = rows
        let lastBin = n / 2 - 1  // bin 0 is DC/Nyquist; skip it
        let binPerHz = Double(n) / sampleRate
        for r in 0..<rows {
            let lower = Self.frequency(row: Double(r), fMin: fMin, fMax: fMax, rows: rows) * binPerHz
            let upper = Self.frequency(row: Double(r + 1), fMin: fMin, fMax: fMax, rows: rows) * binPerHz
            let center = Self.frequency(row: Double(r) + 0.5, fMin: fMin, fMax: fMax, rows: rows)
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

    /// Fractional row index whose center is `f`.
    func row(for f: Double) -> Double {
        Double(rows) * Self.position(of: f, fMin: fMin, fMax: fMax) - 0.5
    }

    /// Height of `f` on the axis, 0 at fMin to 1 at fMax. Labels and the shader's tilt use this
    /// same mapping, so they can't drift from the data.
    static func position(of f: Double, fMin: Double, fMax: Double) -> Double {
        log(f / fMin) / log(fMax / fMin)
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
            let q = ((v + 120) / 120 * 255).rounded()  // tilt is applied in the shader
            out[r] = q.isNaN ? 0 : UInt8(min(max(q, 0), 255))
        }
    }
}
