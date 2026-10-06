import Testing
@testable import Scope

@Test func goniometerMapping() {
    let left = goniometerPoint(l: 1, r: 0)
    #expect(left.x < 0 && left.y > 0)    // upper left
    let right = goniometerPoint(l: 0, r: 1)
    #expect(right.x > 0 && right.y > 0)  // upper right
    let mono = goniometerPoint(l: 0.5, r: 0.5)
    #expect(mono.x == 0 && mono.y > 0)   // vertical
    let antiphase = goniometerPoint(l: 0.5, r: -0.5)
    #expect(antiphase.y == 0 && antiphase.x < 0)  // horizontal
    let full = goniometerPoint(l: 1, r: 1)
    #expect(full.x == 0 && abs(full.y - Float(2).squareRoot()) < 1e-6)  // top vertex: half-diagonal √2
}
