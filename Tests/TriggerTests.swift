import Foundation
import Testing
@testable import Scope

private let window = 1024
private let sine: [Float] = (0..<2 * window).map { Float(sin(2 * Double.pi * 440 * Double($0) / 48_000)) }
private let square: [Float] = (0..<2 * window).map { $0 % 100 < 50 ? 1 : -1 }  // rises at 100k, falls at 100k+50

private func trigger(_ x: [Float], level: Float = 0, _ edge: TriggerEdge) -> Int? {
    x.withUnsafeBufferPointer { findTrigger($0, level: level, edge: edge, maxIndex: window) }
}

@Test func sineRisingLandsOnLatestUpwardCrossing() throws {
    let i = try #require(trigger(sine, .rising))
    #expect(sine[i - 1] < 0 && sine[i] >= 0)
    #expect(i > window - 110)  // one 440 Hz period ≈ 109 samples
}

@Test func sineFallingLandsOnLatestDownwardCrossing() throws {
    let i = try #require(trigger(sine, .falling))
    #expect(sine[i - 1] > 0 && sine[i] <= 0)
    #expect(i > window - 110)
}

@Test func squareHitsKnownTransitions() {
    #expect(trigger(square, .rising) == 1000)
    #expect(trigger(square, .falling) == 950)
    #expect(trigger(square, level: 0.5, .rising) == 1000)
}

@Test func noCrossingFallsBackPerMode() {
    #expect(trigger(sine, level: 2, .rising) == nil)
    sine.withUnsafeBufferPointer { x in
        #expect(frameStart(x, window: window, level: 2, edge: .rising, mode: .auto) == window)
        #expect(frameStart(x, window: window, level: 2, edge: .rising, mode: .normal) == nil)
    }
}
