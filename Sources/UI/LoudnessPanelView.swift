import SwiftUI

private let scaleTop = 6.0, scaleBottom = -60.0

/// M / S / I loudness bars on the app background. Pause and Reset live in the panel's context menu and the R key.
struct LoudnessPanelView: View {
    let snapshot: MeterSnapshot
    let target: Double

    var body: some View {
        bars
            .padding(.vertical, 12)
            .padding(.leading, 2)
            .padding(.trailing, 6)
    }

    private var bars: some View {
        Canvas { context, size in
            let arrowWidth: CGFloat = 10, nameHeight: CGFloat = 16
            let top: CGFloat = 0, bottom = size.height - nameHeight
            func y(_ lufs: Double) -> CGFloat {
                let v = min(max(lufs, scaleBottom), scaleTop)
                return top + (scaleTop - v) / (scaleTop - scaleBottom) * (bottom - top)
            }
            let area = CGRect(x: arrowWidth, y: top, width: size.width - arrowWidth, height: bottom - top)

            let values: [(String, Double?)] = [("M", snapshot.momentary), ("S", snapshot.shortTerm),
                                               ("I", snapshot.integrated)]
            let slot = area.width / CGFloat(values.count)
            let barWidth = slot * 0.75
            let barsMinX = area.minX + (slot - barWidth) / 2, barsMaxX = area.maxX - (slot - barWidth) / 2

            // Target: thin line spanning only the bars, drawn first so the bar fills sit over it,
            // plus an arrow left of the first bar.
            let ty = y(target)
            var line = Path()
            line.move(to: CGPoint(x: barsMinX, y: ty))
            line.addLine(to: CGPoint(x: barsMaxX, y: ty))
            context.stroke(line, with: .color(.vuNeedleOrange), lineWidth: 1)
            var arrow = Path()
            arrow.move(to: CGPoint(x: barsMinX - 1, y: ty))
            arrow.addLine(to: CGPoint(x: barsMinX - 8, y: ty - 5))
            arrow.addLine(to: CGPoint(x: barsMinX - 8, y: ty + 5))
            arrow.closeSubpath()
            context.fill(arrow, with: .color(.vuNeedleOrange))

            for (i, (name, value)) in values.enumerated() {
                let x = area.minX + slot * (CGFloat(i) + 0.5)
                let bar = CGRect(x: x - barWidth / 2, y: area.minY, width: barWidth, height: area.height)
                context.fill(Path(bar), with: .color(.white.opacity(0.06)))
                if let value, value > scaleBottom {
                    let below = CGRect(x: bar.minX, y: y(min(value, target)), width: barWidth,
                                       height: bottom - y(min(value, target)))
                    context.fill(Path(below), with: .color(.scopeBlueGray.opacity(0.55)))
                    if value > target {
                        context.fill(Path(CGRect(x: bar.minX, y: y(value), width: barWidth,
                                                 height: y(target) - y(value))), with: .color(.scopeBlueGray))
                    }
                }
                context.draw(Text(name).font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.scopeBlueGray),
                             at: CGPoint(x: x, y: bottom + nameHeight / 2))
            }
        }
    }
}
