import SwiftUI

/// Goniometer mapping, screen-style axes with +y up.
/// Mono (L == R) goes straight up, L-only to the upper left, R-only to the upper right,
/// L == -R (out of phase) goes horizontal. Matches the reference panel.
@inline(__always)
func goniometerPoint(l: Float, r: Float) -> (x: Float, y: Float) {
    let k: Float = 0.70710678               // 1/sqrt(2)
    return (x: (r - l) * k, y: (l + r) * k)
}

/// XY display rotated 45°: mono is vertical, L-only leans left, out-of-phase is horizontal.
struct GoniometerView: View {
    let feed: StereoFeed
    let gain: Float
    let background: Color
    let date: Date  // changes every display frame to force a redraw
    @State private var buffers = GoniometerBuffers()

    var body: some View {
        Canvas { context, size in
            _ = date
            context.stroke(buffers.path(feed: feed, gain: gain, size: size),
                           with: .color(.scopeBlueGray.opacity(0.7)), lineWidth: 1)
        }
        .background(background)
    }
}

private final class GoniometerBuffers {
    private static let count = 2048  // ~43 ms @ 48 kHz
    private let l = UnsafeMutablePointer<Float>.allocate(capacity: count)
    private let r = UnsafeMutablePointer<Float>.allocate(capacity: count)

    deinit {
        l.deallocate()
        r.deallocate()
    }

    func path(feed: StereoFeed, gain: Float, size: CGSize) -> Path {
        feed.latest(Self.count, l: l, r: r)
        let cx = size.width / 2, cy = size.height / 2
        let k = CGFloat(gain) * min(cx, cy) * 0.95  // goniometerPoint already applies 1/√2
        var path = Path()
        for i in 0..<Self.count {
            let g = goniometerPoint(l: l[i], r: r[i])
            // Canvas y grows downward.
            let p = CGPoint(x: cx + CGFloat(g.x) * k, y: cy - CGFloat(g.y) * k)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
}
