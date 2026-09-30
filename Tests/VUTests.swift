import Foundation
import Testing
@testable import Scope

private let rate = 48_000.0
private let ref = Float(pow(10, -18.0 / 20))    // -18 dBFS RMS
private let peak = ref * 2.0.squareRoot().float  // 0.1778

private extension Double { var float: Float { Float(self) } }

/// Runs `ms` milliseconds of a 1 kHz sine (or silence) through `vu` in 1 ms blocks and returns the
/// linear RMS-equivalent reading after each block. 48 samples = one 1 kHz period, so every block
/// ends on the same phase and ripple doesn't move the readings.
private func run(_ vu: inout VUBallistics, ms: Int, amplitude: Float) -> [Float] {
    var block = [Float](repeating: 0, count: 48)
    var out: [Float] = []
    for _ in 0..<ms {
        for i in 0..<48 { block[i] = amplitude * Float(sin(2 * .pi * Double(i) / 48)) }
        let db = block.withUnsafeBufferPointer { vu.process($0, refRMS: 1) }
        out.append(pow(10, db / 20))
    }
    return out
}

@Test func steadySineAtReferenceReadsZeroVU() {
    var vu = VUBallistics(sampleRate: rate)
    let readings = run(&vu, ms: 1000, amplitude: peak)
    let reading = 20 * log10(readings.last! / ref)
    #expect(abs(reading) < 0.1)
}

@Test func riseReaches99PercentAt300ms() {
    var vu = VUBallistics(sampleRate: rate)
    let readings = run(&vu, ms: 2000, amplitude: peak)
    let final = readings.last!
    let t = readings.firstIndex { $0 >= 0.99 * final }! + 1
    #expect(abs(t - 300) <= 15, "reached 99% at \(t) ms")
}

@Test func fallMatchesRise() {
    var vu = VUBallistics(sampleRate: rate)
    let start = run(&vu, ms: 2000, amplitude: peak).last!
    let readings = run(&vu, ms: 1000, amplitude: 0)
    let t = readings.firstIndex { $0 <= 0.01 * start }! + 1
    #expect(abs(t - 300) <= 15, "fell to 1% at \(t) ms")
}

@Test func needleFractionIsLinearInAmplitude() {
    #expect(abs(needleFraction(vu: -20) - 0.1 / 1.4125) < 1e-4)
    #expect(abs(needleFraction(vu: 0) - 1 / 1.4125) < 1e-4)
    #expect(needleFraction(vu: 10) == 1)
}
