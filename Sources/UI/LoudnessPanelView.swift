import SwiftUI

private let navy = Color(red: 0.09, green: 0.12, blue: 0.17)
private let yellow = Color(red: 1.0, green: 0.80, blue: 0.0)
private let blue = Color(red: 0.31, green: 0.55, blue: 0.72)
private let lightBlue = Color(red: 0.55, green: 0.80, blue: 1.0)

private let scaleTop = 6.0, scaleBottom = -60.0
private let gridlines: [Double] = [0, -3, -6, -9, -12, -16, -20, -24, -30, -40, -50, -60]

/// M / S / I loudness bars with LRA and integrated readouts.
struct LoudnessPanelView: View {
    let snapshot: MeterSnapshot
    let target: Double
    let showPeaks: Bool
    let showButtons: Bool
    @Binding var held: Bool
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            bars
            VStack(spacing: 4) {
                readout("LU Range", snapshot.loudnessRange.map { String(format: "%.1f LU", $0) })
                readout("Integrated", snapshot.integrated.map { String(format: "%.1f LUFS", $0) })
                if showPeaks {
                    readout("Peak", String(format: "%.1f dBFS", snapshot.samplePeak))
                    readout("True Peak", String(format: "%.1f dBTP", snapshot.truePeak))
                }
            }
            .foregroundStyle(lightBlue)
            if showButtons {
                HStack {
                    Toggle(held ? "Paused" : "Pause", isOn: $held).toggleStyle(.button)
                    Button("Reset", action: onReset)
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(navy)
    }

    private func readout(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value ?? "—").monospacedDigit()
        }
        .font(.system(size: 12, weight: .medium))
    }

    private var bars: some View {
        Canvas { context, size in
            let labelWidth: CGFloat = 26, valueHeight: CGFloat = 20, nameHeight: CGFloat = 16
            let top = valueHeight + 4, bottom = size.height - nameHeight
            func y(_ lufs: Double) -> CGFloat {
                let v = min(max(lufs, scaleBottom), scaleTop)
                return top + (scaleTop - v) / (scaleTop - scaleBottom) * (bottom - top)
            }
            let area = CGRect(x: labelWidth, y: top, width: size.width - labelWidth, height: bottom - top)

            for g in gridlines {
                var line = Path()
                line.move(to: CGPoint(x: area.minX, y: y(g)))
                line.addLine(to: CGPoint(x: area.maxX, y: y(g)))
                context.stroke(line, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
                context.draw(Text(String(Int(g))).font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5)),
                             at: CGPoint(x: labelWidth - 4, y: y(g)), anchor: .trailing)
            }

            let values: [(String, Double?)] = [("M", snapshot.momentary), ("S", snapshot.shortTerm),
                                               ("I", snapshot.integrated)]
            let slot = area.width / CGFloat(values.count)
            let barWidth = slot * 0.55
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
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(yellow),
                             at: CGPoint(x: x, y: valueHeight / 2))
                context.draw(Text(name).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.8)),
                             at: CGPoint(x: x, y: bottom + nameHeight / 2))
            }

            // Target: thin line across the bars plus an arrow on the left edge.
            let ty = y(target)
            var line = Path()
            line.move(to: CGPoint(x: area.minX, y: ty))
            line.addLine(to: CGPoint(x: area.maxX, y: ty))
            context.stroke(line, with: .color(yellow.opacity(0.8)), lineWidth: 1)
            var arrow = Path()
            arrow.move(to: CGPoint(x: area.minX - 1, y: ty))
            arrow.addLine(to: CGPoint(x: area.minX - 8, y: ty - 5))
            arrow.addLine(to: CGPoint(x: area.minX - 8, y: ty + 5))
            arrow.closeSubpath()
            context.fill(arrow, with: .color(yellow))
        }
    }
}
