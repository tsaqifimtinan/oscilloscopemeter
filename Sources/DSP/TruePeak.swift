import Foundation

/// 4× oversampled true-peak detector: a 48-tap polyphase interpolator (12 taps per phase).
/// Allocates only in `init`.
///
/// Deviation from BS.1770-4 Annex 2: the taps are a Hann-windowed sinc rather than the exact
/// coefficient table in the recommendation. It reads within ~0.1 dB for content below ~16 kHz;
/// swap in the Annex 2 table if you need conformance-grade readings near Nyquist.
struct TruePeak {
    private static let phases = 4, taps = 12
    private static let coefficients: [[Double]] = {
        let length = phases * taps, center = Double(length - 1) / 2
        let h = (0..<length).map { k -> Double in
            let x = (Double(k) - center) / Double(phases)
            let sinc = x == 0 ? 1 : sin(.pi * x) / (.pi * x)
            let hann = 0.5 - 0.5 * cos(2 * .pi * (Double(k) + 0.5) / Double(length))
            return sinc * hann
        }
        // Phase p uses h[4j + p]; normalize each phase to unity DC gain.
        return (0..<phases).map { p in
            let phase = (0..<taps).map { h[$0 * phases + p] }
            let sum = phase.reduce(0, +)
            return phase.map { $0 / sum }
        }
    }()

    private var history = [Double](repeating: 0, count: taps)  // ring of recent input samples
    private var position = 0

    /// Largest absolute value of the oversampled block (never below the sample peak).
    mutating func process(_ x: UnsafePointer<Float>, count: Int) -> Float {
        var peak = 0.0
        for i in 0..<count {
            let sample = Double(x[i])
            position = (position + 1) % Self.taps
            history[position] = sample
            peak = max(peak, abs(sample))
            for p in 0..<Self.phases {
                let c = Self.coefficients[p]
                var y = 0.0
                for j in 0..<Self.taps { y += c[j] * history[(position - j + Self.taps) % Self.taps] }
                peak = max(peak, abs(y))
            }
        }
        return Float(peak)
    }

    mutating func reset() {
        for i in history.indices { history[i] = 0 }
    }
}
