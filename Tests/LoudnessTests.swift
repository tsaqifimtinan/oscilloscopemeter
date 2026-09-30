import Foundation
import Testing
@testable import Scope

/// Synthetic 997 Hz sine source with a running phase, fed to a meter in 100 ms chunks.
private struct Signal {
    var t = 0

    /// Peak amplitudes in dBFS; nil = digital silence on that channel.
    mutating func run(_ meter: inout LoudnessMeter, seconds: Double, left: Double?, right: Double?,
                      frequency: Double = 997) {
        let chunk = LoudnessMeter.hopSamples
        var l = [Float](repeating: 0, count: chunk), r = l
        let al = left.map { Float(pow(10, $0 / 20)) } ?? 0
        let ar = right.map { Float(pow(10, $0 / 20)) } ?? 0
        for _ in 0..<Int(seconds * 10) {
            for i in 0..<chunk {
                let s = Float(sin(2 * .pi * frequency * Double(t + i) / 48_000))
                l[i] = al * s
                r[i] = ar * s
            }
            t += chunk
            meter.process(l: l, r: r, count: chunk)
        }
    }

    /// Stereo sine whose loudness is `lufs` (for a stereo 997 Hz sine, peak dBFS == LUFS).
    mutating func run(_ meter: inout LoudnessMeter, seconds: Double, lufs: Double?) {
        run(&meter, seconds: seconds, left: lufs, right: lufs)
    }
}

private func near(_ value: Double?, _ expected: Double, _ tolerance: Double = 0.1) -> Bool {
    guard let value else { return false }
    return abs(value - expected) <= tolerance
}

@Test func stereoSineAtMinus23() {
    var meter = LoudnessMeter(), signal = Signal()
    signal.run(&meter, seconds: 10, lufs: -23)
    #expect(near(meter.momentary, -23), "M \(String(describing: meter.momentary))")
    #expect(near(meter.shortTerm, -23), "S \(String(describing: meter.shortTerm))")
    #expect(near(meter.integrated, -23), "I \(String(describing: meter.integrated))")
}

@Test func singleChannelSameEnergy() {
    var meter = LoudnessMeter(), signal = Signal()
    signal.run(&meter, seconds: 10, left: -20, right: nil)
    #expect(near(meter.integrated, -23), "I \(String(describing: meter.integrated))")
}

@Test func fullScaleStereoSineReadsZero() {
    var meter = LoudnessMeter(), signal = Signal()
    signal.run(&meter, seconds: 10, lufs: 0)
    #expect(near(meter.integrated, 0), "I \(String(describing: meter.integrated))")
}

@Test func absoluteAndRelativeGates() throws {
    var meter = LoudnessMeter(), signal = Signal()
    signal.run(&meter, seconds: 10, lufs: -23)
    signal.run(&meter, seconds: 30, lufs: nil)
    let afterSilence = try #require(meter.integrated)
    #expect(near(afterSilence, -23), "after silence \(afterSilence)")
    signal.run(&meter, seconds: 10, lufs: -50)
    #expect(near(meter.integrated, afterSilence, 0.01), "after -50 LUFS \(String(describing: meter.integrated))")
}

@Test func loudnessRange() {
    var constant = LoudnessMeter(), signal = Signal()
    signal.run(&constant, seconds: 20, lufs: -23)
    #expect(near(constant.loudnessRange, 0), "constant LRA \(String(describing: constant.loudnessRange))")

    var stepped = LoudnessMeter()
    signal.run(&stepped, seconds: 20, lufs: -30)
    signal.run(&stepped, seconds: 20, lufs: -20)
    #expect(near(stepped.loudnessRange, 10, 0.5), "stepped LRA \(String(describing: stepped.loudnessRange))")
}

@Test func holdFreezesIntegratedAndResetClears() {
    var meter = LoudnessMeter(), signal = Signal()
    signal.run(&meter, seconds: 10, lufs: -23)
    meter.held = true
    signal.run(&meter, seconds: 10, lufs: -14)
    #expect(near(meter.integrated, -23), "held I \(String(describing: meter.integrated))")
    #expect(near(meter.momentary, -14), "M keeps moving while held")

    meter.reset()
    #expect(meter.integrated == nil && meter.momentary == nil && meter.loudnessRange == nil)
    meter.held = false
    signal.run(&meter, seconds: 5, lufs: -14)
    #expect(near(meter.integrated, -14), "I after reset \(String(describing: meter.integrated))")
}

@Test func truePeakFindsInterSamplePeak() {
    // 12 kHz = fs/4 at 45° phase: samples sit at ±0.707·A, the waveform peaks at A.
    let amplitude: Float = 0.5
    let x = (0..<4800).map { amplitude * Float(sin(2 * .pi * Double($0) / 4 + .pi / 4)) }
    var tp = TruePeak()
    let peak = x.withUnsafeBufferPointer { tp.process($0.baseAddress!, count: $0.count) }
    let samplePeak = x.map(abs).max()!
    #expect(abs(20 * log10(samplePeak / amplitude) - -3.01) < 0.01)
    #expect(abs(20 * log10(peak / amplitude)) < 0.2, "true peak \(20 * log10(peak)) dBTP")
}
