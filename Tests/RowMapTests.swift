import Foundation
import SwiftUI
import Testing
@testable import Scope

private func map(n: Int = 4096, range: FrequencyRange = .full) -> RowMap {
    RowMap(fftSize: n, fMin: range.bounds.min, fMax: range.bounds.max, rows: 512, sampleRate: 48_000)
}

func quantize(_ db: [Float], _ m: RowMap) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: m.rows)
    db.withUnsafeBufferPointer { m.apply(db: $0.baseAddress!, into: &out) }
    return out
}

func argmax(_ column: [UInt8]) -> Int { column.indices.max { column[$0] < column[$1] }! }

@Test func oneKilohertzLandsOnItsRow() {
    let m = map()
    let column = quantize(spectrum(sine(1000, count: 4096)), m)
    // PLAN-4 says "about 290": 512·ln(50)/ln(1000) = 289.9 is a row *edge*; the row centered on 1 kHz is 289.4.
    #expect(abs(m.row(for: 1000) - 289.4) < 0.1)
    #expect(abs(argmax(column) - 289) <= 3)
}

@Test(arguments: [2048, 4096, 8192], FrequencyRange.allCases)
func rowMapIsWellFormed(n: Int, range: FrequencyRange) {
    let m = map(n: n, range: range)
    for r in 0..<m.rows {
        #expect(m.lo[r] >= 1 && m.lo[r] <= m.hi[r] && m.hi[r] <= n / 2 - 1)
        #expect((0...1).contains(m.frac[r]))
        if r > 0 { #expect(m.lo[r] >= m.lo[r - 1] && m.hi[r] >= m.hi[r - 1]) }
    }
    #expect(m.firstMaxRow > 0 && m.firstMaxRow < m.rows)  // both regimes used
}

@Test func silenceQuantizesToZero() {
    #expect(quantize(spectrum([Float](repeating: 0, count: 4096)), map()).allSatisfy { $0 == 0 })
}

@Test(arguments: FrequencyRange.allCases)
func labelsSitOnTheirRows(range: FrequencyRange) {
    let m = RowMap(fftSize: 4096, fMin: range.bounds.min, fMax: range.bounds.max, rows: 512, sampleRate: 48_000)
    let height: CGFloat = 540
    let rowY = height * (1 - (m.row(for: 1000) + 0.5) / 512)  // center of the 1 kHz row, from the top
    #expect(abs(FrequencyLabels.y(of: 1000, range: range, height: height) - rowY) < 1e-9)
}
