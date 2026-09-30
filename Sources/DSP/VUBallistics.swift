import Foundation

/// Standard VU ballistics: 99% of the final reading at 300 ms, symmetric fall.
/// A critically damped 2nd-order response = two cascaded one-pole low-passes (tau 45.2 ms each)
/// on the rectified signal.
struct VUBallistics {
    private var s1: Float = 0, s2: Float = 0
    private let a: Float

    init(sampleRate: Double, tau: Double = 0.0452) {
        a = Float(1 - exp(-1 / (tau * sampleRate)))  // one-pole coefficient per sample
    }

    /// Processes a block; returns the reading in VU where 0 VU == `refRMS` (linear).
    /// With `refRMS: 1` the result is the level in dBFS (RMS-equivalent).
    mutating func process(_ x: UnsafeBufferPointer<Float>, refRMS: Float) -> Float {
        for v in x {
            s1 += a * (abs(v) - s1)  // rectify + stage 1
            s2 += a * (s1 - s2)      // stage 2
        }
        // Mean of |sine| is 2/π·peak and its RMS is peak/√2, so scale by π/(2√2):
        // a steady sine reads its RMS level (this is how VU is calibrated).
        let rmsEquivalent = s2 * 1.1107207
        return 20 * log10(max(rmsEquivalent / refRMS, 1e-6))
    }
}

/// The scale is linear in amplitude: -20 VU = 10%, 0 VU = 100%, +3 VU = 141%.
func needleFraction(vu: Float) -> Float {
    min(pow(10, vu / 20), 1.4125) / 1.4125  // 0...1 across the arc
}
