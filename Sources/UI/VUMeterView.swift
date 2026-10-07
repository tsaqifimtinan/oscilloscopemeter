import SwiftUI

// Geometry knobs: tune these to match the reference image.
private let swingDegrees = 40.0              // needle travel each side of vertical
private let arcRadiusOfWidth: CGFloat = 0.62 // scale radius as a fraction of meter width
private let arcRadiusOfHeight: CGFloat = 1.2 // …capped by this fraction of meter height
private let needleWidth: CGFloat = 5

private let labels: [Float] = [-20, -10, -7, -5, -4, -3, -2, -1, 0, 1, 2, 3]
private let percents: [Float] = [0, 20, 40, 60, 80, 100]

/// Analog VU meter(s): one needle for mono/sum, or L and R side by side.
struct VUMeterView: View {
    let snapshot: MeterSnapshot
    let reference: Float  // dBFS RMS that reads 0 VU
    let mono: Bool
    let background: Color

    var body: some View {
        HStack(spacing: 0) {
            if mono {
                VUMeter(vu: snapshot.vuMono - reference, label: "L+R")
            } else {
                VUMeter(vu: snapshot.vuL - reference, label: "L")
                VUMeter(vu: snapshot.vuR - reference, label: "R")
            }
        }
        .background(background)
    }
}

private struct VUMeter: View {
    let vu: Float
    let label: String

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let radius = min(w * arcRadiusOfWidth, h * arcRadiusOfHeight)
            let fontSize = max(9, min(18, radius * 0.075))
            // Center the visible block (labels above the arc down to the clip line) vertically.
            let apexY = max((h - radius * 0.45) / 2 + fontSize * 1.5, radius * 0.12 + 20)
            let pivot = CGPoint(x: w / 2, y: apexY + radius)

            /// Point on the arc at `fraction` (0…1 across the scale) and `r` from the pivot.
            func point(_ fraction: Float, _ r: CGFloat) -> CGPoint {
                let angle = (-swingDegrees + 2 * swingDegrees * Double(fraction)) * .pi / 180
                return CGPoint(x: pivot.x + r * sin(angle), y: pivot.y - r * cos(angle))
            }
            func arc(from a: Float, to b: Float, radius r: CGFloat) -> Path {
                Path { p in
                    let steps = 48
                    for i in 0...steps {
                        let f = a + (b - a) * Float(i) / Float(steps)
                        i == 0 ? p.move(to: point(f, r)) : p.addLine(to: point(f, r))
                    }
                }
            }

            let zero = needleFraction(vu: 0)
            context.clip(to: Path(CGRect(x: 0, y: 0, width: w, height: min(h, apexY + radius * 0.45))))

            // Baselines: thin blue-gray up to 0 VU, thick red from 0 to +3.
            context.stroke(arc(from: 0, to: zero, radius: radius), with: .color(.scopeBlueGray), lineWidth: 1.5)
            context.stroke(arc(from: zero, to: 1, radius: radius + 3), with: .color(.vuRed), lineWidth: 6)

            // Top row: VU marks and labels.
            for value in labels {
                let f = needleFraction(vu: value)
                let color = value > 0 ? Color.vuRed : Color.scopeBlueGray
                var tick = Path()
                tick.move(to: point(f, radius + 6))
                tick.addLine(to: point(f, radius + 14))
                context.stroke(tick, with: .color(color), lineWidth: 1.5)
                let text = Text(String(Int(abs(value))))
                    .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                context.draw(text, at: point(f, radius + 14 + fontSize * 0.9))
            }

            // Second row: percent dots under the blue portion.
            for pct in percents {
                let f = pct / 100 / 1.4125
                let dot = point(f, radius - 10)
                context.fill(Path(ellipseIn: CGRect(x: dot.x - 2, y: dot.y - 2, width: 4, height: 4)),
                             with: .color(.scopeBlueGray))
                context.draw(Text(String(Int(pct)))
                                .font(.system(size: fontSize * 0.6, design: .monospaced))
                                .foregroundStyle(Color.scopeBlueGray.opacity(0.8)),
                             at: point(f, radius - 10 - fontSize * 0.9))
            }

            context.draw(Text("VU").font(.system(size: fontSize * 1.2, weight: .bold)).foregroundStyle(Color.scopeBlueGray),
                         at: CGPoint(x: pivot.x, y: apexY + radius * 0.3))
            context.draw(Text(label).font(.system(size: fontSize * 0.7, design: .monospaced)).foregroundStyle(Color.scopeBlueGray),
                         at: CGPoint(x: 16, y: apexY + radius * 0.35), anchor: .leading)

            // Needle, pivoting below the visible scale.
            var needle = Path()
            needle.move(to: pivot)
            needle.addLine(to: point(needleFraction(vu: vu), radius + 12))
            context.stroke(needle, with: .color(.vuNeedleOrange),
                           style: StrokeStyle(lineWidth: needleWidth, lineCap: .round))
        }
    }
}
