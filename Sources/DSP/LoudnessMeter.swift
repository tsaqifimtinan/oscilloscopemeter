import Foundation

/// Loudness of a mean-square energy (sum over channels, weights 1.0 for L/R), BS.1770.
func loudness(_ z: Double) -> Double {
    -0.691 + 10 * log10(z)
}

/// BS.1770-4 / EBU R128 meter: momentary (400 ms), short-term (3 s), integrated (gated) and
/// loudness range (EBU Tech 3342). Feed it every sample exactly once, in order, at 48 kHz.
/// Allocates only in `init`; `reset()` clears in place.
struct LoudnessMeter {
    static let hopSamples = 4_800  // 100 ms @ 48 kHz
    private static let shortTermHops = 30

    private var kL = KWeighting(), kR = KWeighting()
    private var hopEnergy = 0.0, hopFill = 0
    private var hops = [Double](repeating: 0, count: shortTermHops)  // ring of recent hop energies
    private var hopsSeen = 0
    private var blocks = LoudnessHistogram()      // 400 ms gating blocks → integrated
    private var shortTerms = LoudnessHistogram()  // short-term values → LRA

    /// While held, integrated and LRA stop accumulating (and so freeze); M and S keep moving.
    var held = false
    private(set) var momentary: Double?
    private(set) var shortTerm: Double?

    var integrated: Double? { blocks.gatedLoudness(relativeGate: -10) }
    var loudnessRange: Double? { shortTerms.range(relativeGate: -20) }

    mutating func process(l: UnsafePointer<Float>, r: UnsafePointer<Float>, count: Int) {
        for i in 0..<count {
            let a = kL.process(l[i]), b = kR.process(r[i])
            hopEnergy += a * a + b * b
            hopFill += 1
            if hopFill == Self.hopSamples { finishHop() }
        }
    }

    /// Clears all measurements and the K-filter state; keeps `held`.
    mutating func reset() {
        kL = KWeighting()
        kR = KWeighting()
        (hopEnergy, hopFill, hopsSeen) = (0, 0, 0)
        for i in hops.indices { hops[i] = 0 }
        blocks.clear()
        shortTerms.clear()
        momentary = nil
        shortTerm = nil
    }

    private mutating func finishHop() {
        hops[hopsSeen % Self.shortTermHops] = hopEnergy / Double(Self.hopSamples)
        hopsSeen += 1
        (hopEnergy, hopFill) = (0, 0)
        // Each hop closes one 400 ms block (4 hops, 75% overlap) and one 3 s window (30 hops).
        if hopsSeen >= 4 {
            let z = meanOfLastHops(4)
            momentary = loudness(z)
            if !held { blocks.add(z) }
        }
        if hopsSeen >= Self.shortTermHops {
            let z = meanOfLastHops(Self.shortTermHops)
            shortTerm = loudness(z)
            if !held { shortTerms.add(z) }
        }
    }

    private func meanOfLastHops(_ n: Int) -> Double {
        var sum = 0.0
        for k in 1...n { sum += hops[(hopsSeen - k) % Self.shortTermHops] }
        return sum / Double(n)
    }
}

/// Energies binned by loudness in 0.1 LU bins from -70 to +10 LUFS, so memory stays O(1) for
/// hours-long sessions. Adding applies the -70 LUFS absolute gate. Gated means use the exact bin
/// energy sums; only the relative-gate threshold and percentiles are quantized to 0.1 LU.
struct LoudnessHistogram {
    private static let floor = -70.0, binWidth = 0.1
    private static let binCount = 800
    private var counts = [Int](repeating: 0, count: binCount)
    private var energies = [Double](repeating: 0, count: binCount)

    mutating func add(_ z: Double) {
        let l = loudness(z)
        guard l >= Self.floor else { return }  // absolute gate
        let bin = Swift.min(Int((l - Self.floor) / Self.binWidth), Self.binCount - 1)
        counts[bin] += 1
        energies[bin] += z
    }

    mutating func clear() {
        for i in counts.indices {
            counts[i] = 0
            energies[i] = 0
        }
    }

    /// Integrated loudness: mean energy of the blocks at or above (ungated mean + `relativeGate`).
    func gatedLoudness(relativeGate: Double) -> Double? {
        guard let start = relativeGateBin(relativeGate) else { return nil }
        var n = 0, e = 0.0
        for b in start..<Self.binCount {
            n += counts[b]
            e += energies[b]
        }
        return n > 0 ? loudness(e / Double(n)) : nil
    }

    /// Loudness range: 95th minus 10th percentile of the values at or above the relative gate.
    func range(relativeGate: Double) -> Double? {
        guard let start = relativeGateBin(relativeGate) else { return nil }
        let n = counts[start...].reduce(0, +)
        guard n > 0 else { return nil }
        func percentile(_ p: Double) -> Double {
            var cumulative = 0
            for b in start..<Self.binCount {
                cumulative += counts[b]
                if Double(cumulative) >= p * Double(n) { return Self.floor + (Double(b) + 0.5) * Self.binWidth }
            }
            return Self.floor + Double(Self.binCount) * Self.binWidth
        }
        return percentile(0.95) - percentile(0.10)
    }

    /// First bin at or above the relative gate, or nil if nothing passed the absolute gate.
    private func relativeGateBin(_ relativeGate: Double) -> Int? {
        var n = 0, e = 0.0
        for b in 0..<Self.binCount {
            n += counts[b]
            e += energies[b]
        }
        guard n > 0 else { return nil }
        let gate = loudness(e / Double(n)) + relativeGate
        return Swift.max(0, Swift.min(Self.binCount - 1, Int(((gate - Self.floor) / Self.binWidth).rounded(.down))))
    }
}
