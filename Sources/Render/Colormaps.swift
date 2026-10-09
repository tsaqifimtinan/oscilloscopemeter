/// Spectrogram colormaps: evenly spaced stops, expanded to a 256-entry RGBA8 lookup table.
enum Colormap: String, Codable, CaseIterable, Sendable {
    case ice = "Ice", magma = "Magma", viridis = "Viridis"

    /// RGB stops, 0…1, evenly spaced from quiet to loud.
    var stops: [SIMD3<Float>] {
        switch self {
        case .ice:  // ends on the scope's blue-gray (Color.scopeBlueGray), then white
            [.init(0, 0, 0), .init(0.06, 0.10, 0.20), .init(0.30, 0.42, 0.65), .init(0.66, 0.75, 0.92), .init(1, 1, 1)]
        case .magma:  // matplotlib key colors
            [0x000004, 0x1c1044, 0x4f127b, 0x812581, 0xb5367a, 0xe55964, 0xfb8761, 0xfec287, 0xfcfdbf].map(Self.rgb)
        case .viridis:
            [0x440154, 0x482878, 0x3e4989, 0x31688e, 0x26828e, 0x1f9e89, 0x35b779, 0x6ece58, 0xfde725].map(Self.rgb)
        }
    }

    /// 256 × RGBA8, piecewise-linear between the stops.
    var lut: [UInt8] {
        let s = stops
        return (0..<256).flatMap { i -> [UInt8] in
            let x = Float(i) / 255 * Float(s.count - 1)
            let k = min(Int(x), s.count - 2)
            let c = s[k] + (s[k + 1] - s[k]) * (x - Float(k))
            return [c.x, c.y, c.z, 1].map { UInt8(($0 * 255).rounded()) }
        }
    }

    private static func rgb(_ hex: Int) -> SIMD3<Float> {
        SIMD3(Float(hex >> 16 & 0xff), Float(hex >> 8 & 0xff), Float(hex & 0xff)) / 255
    }
}
