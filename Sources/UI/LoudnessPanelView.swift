import SwiftUI

private let navy = Color(red: 0.09, green: 0.12, blue: 0.17)
private let yellow = Color(red: 1.0, green: 0.80, blue: 0.0)
private let blue = Color(red: 0.31, green: 0.55, blue: 0.72)

private let scaleTop = 6.0, scaleBottom = -60.0
private let scaleMarks: [Double] = [0, -3, -6, -9, -12, -16, -20, -24, -30, -40, -50, -60]

/// M / S / I loudness bars. Pause and Reset live in the panel's context menu and the R key.
struct LoudnessPanelView: View {
    let snapshot: MeterSnapshot
    let target: Double
    let showScale: Bool

    var body: some View {
        bars
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background(navy)
    }

    private var bars: some View {
        Canvas { context, size in
            // Without the scale, keep just enough room for the target arrow.
            let labelWidth: CGFloat = showScale ? 24 : 10, valueHeight: CGFloat = 20, nameHeight: CGFloat = 16
            let top = valueHeight + 4, bottom = size.height - nameHeight
            func y(_ lufs: Double) -> CGFloat {
                let v = min(max(lufs, scaleBottom), scaleTop)
                return top + (scaleTop - v) / (scaleTop - scaleBottom) * (bottom - top)
            }
            let area = CGRect(x: labelWidth, y: top, width: size.width - labelWidth, height: bottom - top)

            if showScale {
                for g in scaleMarks {
                    context.draw(Text(String(Int(g))).font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.5)),
                                 at: CGPoint(x: labelWidth - 4, y: y(g)), anchor: .trailing)
                }
            }

            let values: [(String, Double?)] = [("M", snapshot.momentary), ("S", snapshot.shortTerm),
                                               ("I", snapshot.integrated)]
            let slot = area.width / CGFloat(values.count)
            let barWidth = slot * 0.75
            let valueSize = min(14, slot / 3.8)  // "-23.4" fits its slot when the layout squeezes the panel
            let barsMinX = area.minX + (slot - barWidth) / 2, barsMaxX = area.maxX - (slot - barWidth) / 2

            // Target: thin line spanning only the bars, drawn first so the bar fills sit over it,
            // plus an arrow left of the first bar.
            let ty = y(target)
            var line = Path()
            line.move(to: CGPoint(x: barsMinX, y: ty))
            line.addLine(to: CGPoint(x: barsMaxX, y: ty))
            context.stroke(line, with: .color(yellow.opacity(0.8)), lineWidth: 1)
            var arrow = Path()
            arrow.move(to: CGPoint(x: barsMinX - 1, y: ty))
            arrow.addLine(to: CGPoint(x: barsMinX - 8, y: ty - 5))
            arrow.addLine(to: CGPoint(x: barsMinX - 8, y: ty + 5))
            arrow.closeSubpath()
            context.fill(arrow, with: .color(yellow))

            for (i, (name, value)) in values.enumerated() {
                let x = area.minX + slot * (CGFloat(i) + 0.5)
                let bar = CGRect(x: x - barWidth / 2, y: area.minY, width: barWidth, height: area.height)
                context.fill(Path(bar), with: .color(.white.opacity(0.05)))
                if let value, value > scaleBottom {
                    let below = CGRect(x: bar.minX, y: y(min(value, target)), width: barWidth,
                                       height: bottom - y(min(value, target)))
                    context.fill(Path(below), with: .color(blue))
                    if value > target {
                        context.fill(Path(CGRect(x: bar.minX, y: y(value), width: barWidth,
                                                 height: y(target) - y(value))), with: .color(yellow))
                    }
                }
                context.draw(Text(value.map { String(format: "%.1f", $0) } ?? "—")
                                .font(.system(size: valueSize, weight: .bold, design: .monospaced))
                                .foregroundStyle(yellow),
                             at: CGPoint(x: x, y: valueHeight / 2))
                context.draw(Text(name).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.8)),
                             at: CGPoint(x: x, y: bottom + nameHeight / 2))
            }
        }
    }
}
