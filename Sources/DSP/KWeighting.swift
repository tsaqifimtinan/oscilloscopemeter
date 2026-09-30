/// Direct Form I biquad in Double: y[n] = b0 x[n] + b1 x[n-1] + b2 x[n-2] - a1 y[n-1] - a2 y[n-2].
struct Biquad {
    private let b0, b1, b2, a1, a2: Double
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        (self.b0, self.b1, self.b2, self.a1, self.a2) = (b0, b1, b2, a1, a2)
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        (x2, x1, y2, y1) = (x1, x, y1, y)
        return y
    }
}

/// ITU-R BS.1770-4 K-weighting at 48 kHz: stage 1 high shelf, then stage 2 RLB high-pass.
/// Only valid at 48 kHz; the capture path rejects other rates.
struct KWeighting {
    private var shelf = Biquad(b0: 1.53512485958697, b1: -2.69169618940638, b2: 1.19839281085285,
                               a1: -1.69065929318241, a2: 0.73248077421585)
    private var highPass = Biquad(b0: 1.0, b1: -2.0, b2: 1.0,
                                  a1: -1.99004745483398, a2: 0.99007225036621)

    mutating func process(_ x: Float) -> Double {
        highPass.process(shelf.process(Double(x)))
    }
}
