import Foundation
import Testing
@testable import Scope

func sine(_ hz: Double, amplitude: Float = 1, count: Int, sampleRate: Double = 48_000, start: Int = 0) -> [Float] {
    (0..<count).map { amplitude * Float(sin(2 * .pi * hz * Double(start + $0) / sampleRate)) }
}

func spectrum(_ input: [Float], fftSize n: Int = 4096) -> [Float] {
    let analyzer = SpectrumAnalyzer(fftSize: n)
    var db = [Float](repeating: .nan, count: n / 2)
    input.withUnsafeBufferPointer { analyzer.process($0.baseAddress!, dbOut: &db) }
    return db
}

@Test func fullScaleSineOnBinCenterIsZeroDBFS() {
    let db = spectrum(sine(1171.875, count: 4096))  // bin 100 at 4096 / 48 kHz
    #expect(abs(db[100]) < 0.5)
    #expect(db.max()! == db[100])
}

@Test func tenthAmplitudeIsMinus20() {
    let db = spectrum(sine(1171.875, amplitude: 0.1, count: 4096))
    #expect(abs(db[100] + 20) < 0.5)
}

@Test func halfBinSineLosesAtMostScallopLoss() {
    let onBin = spectrum(sine(1171.875, count: 4096))[100]
    let db = spectrum(sine(100.5 * 48_000 / 4096, count: 4096))
    let off = max(db[100], db[101])
    #expect(onBin - off <= 1.5)
    #expect(onBin - off > 1)  // Hann scalloping is ~1.42 dB; a much smaller loss means a wrong window
}

@Test(arguments: [2048, 4096, 8192])
func silenceIsFiniteAndLow(n: Int) {
    let db = spectrum([Float](repeating: 0, count: n), fftSize: n)
    #expect(db.allSatisfy { $0.isFinite && $0 < -150 })
}
