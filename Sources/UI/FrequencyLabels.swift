import SwiftUI

/// Faint frequency marks on the spectrogram's left edge; no lines.
struct FrequencyLabels: View {
    let range: FrequencyRange
    static let marks: [Double] = [50, 100, 200, 500, 1_000, 2_000, 5_000, 10_000]

    /// Distance from the top, from the same log mapping the engine uses for rows.
    static func y(of f: Double, range: FrequencyRange, height: CGFloat) -> CGFloat {
        height * (1 - RowMap.position(of: f, fMin: range.bounds.min, fMax: range.bounds.max))
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(Self.marks, id: \.self) { f in
                let y = Self.y(of: f, range: range, height: geo.size.height)
                if y > 8 && y < geo.size.height - 8 {
                    Text(f >= 1_000 ? "\(Int(f / 1_000))k" : "\(Int(f))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(height: 12)
                        .offset(x: 6, y: y - 6)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
