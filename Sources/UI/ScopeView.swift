import Accelerate
import SwiftUI

struct ScopeSettings {
    static let windows = [512, 1024, 2048, 4096, 8192]
    var window = 1024
    var gain: Float = 1
    var triggerLevel: Float = 0
    var edge = TriggerEdge.rising
    var mode = TriggerMode.auto
}

/// Triggered single-trace scope over the mono mix of the most recent samples in `feed`.
struct ScopeView: View {
    let feed: StereoFeed
    let settings: ScopeSettings
    @State private var buffers = TraceBuffers()

    private static let traceColor = Color(red: 0.66, green: 0.75, blue: 0.92)

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                _ = timeline.date  // redraw every display frame
                context.stroke(buffers.trace(feed: feed, settings: settings, size: size),
                               with: .color(Self.traceColor), lineWidth: 1)
            }
        }
        .background(.black)
    }
}

/// Preallocated snapshot + displayed frame, so drawing doesn't allocate sample storage per frame.
private final class TraceBuffers {
    private static let maxWindow = ScopeSettings.windows.max()!
    private let snapL = UnsafeMutablePointer<Float>.allocate(capacity: 2 * maxWindow)
    private let snapR = UnsafeMutablePointer<Float>.allocate(capacity: 2 * maxWindow)
    private let snapshot = UnsafeMutablePointer<Float>.allocate(capacity: 2 * maxWindow)
    private let frame = UnsafeMutablePointer<Float>.allocate(capacity: maxWindow)

    init() { frame.initialize(repeating: 0, count: Self.maxWindow) }

    deinit {
        snapL.deallocate()
        snapR.deallocate()
        snapshot.deallocate()
        frame.deallocate()
    }

    func trace(feed: StereoFeed, settings: ScopeSettings, size: CGSize) -> Path {
        let w = settings.window
        feed.latest(2 * w, l: snapL, r: snapR)
        var half: Float = 0.5
        vDSP_vasm(snapL, 1, snapR, 1, &half, snapshot, 1, vDSP_Length(2 * w))
        let x = UnsafeBufferPointer(start: snapshot, count: 2 * w)
        if let start = frameStart(x, window: w, level: settings.triggerLevel,
                                  edge: settings.edge, mode: settings.mode) {
            frame.update(from: snapshot + start, count: w)
        }  // else Normal mode without a trigger: keep drawing the held frame

        let mid = size.height / 2
        let gain = CGFloat(settings.gain)
        func y(_ v: Float) -> CGFloat { mid - CGFloat(v) * gain * mid }

        var path = Path()
        let columns = Int(size.width.rounded(.up))
        guard columns > 0 else { return path }
        if w > columns {
            // Min/max per pixel column; each range reaches one sample back so columns connect.
            let perColumn = Double(w) / Double(columns)
            for c in 0..<columns {
                let lo = max(Int(Double(c) * perColumn) - 1, 0)
                let hi = min(Int(Double(c + 1) * perColumn), w)
                var mn: Float = 0, mx: Float = 0
                vDSP_minv(frame + lo, 1, &mn, vDSP_Length(hi - lo))
                vDSP_maxv(frame + lo, 1, &mx, vDSP_Length(hi - lo))
                let top = y(mx)
                let px = CGFloat(c) + 0.5
                path.move(to: CGPoint(x: px, y: top))
                path.addLine(to: CGPoint(x: px, y: max(y(mn), top + 1)))  // ≥1 px so flat lines show
            }
        } else {
            let dx = size.width / CGFloat(w - 1)
            path.move(to: CGPoint(x: 0, y: y(frame[0])))
            for i in 1..<w {
                path.addLine(to: CGPoint(x: CGFloat(i) * dx, y: y(frame[i])))
            }
        }
        return path
    }
}
