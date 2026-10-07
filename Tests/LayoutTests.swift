import CoreGraphics
import Testing
@testable import Scope

@MainActor @Test func wideLayoutsFitEveryShape() {
    let combos: [Set<Panel>] = LayoutPreset.allCases.flatMap { [$0.panels, $0.panels.union([.goniometer])] }
        + [[.goniometer], [.scope, .goniometer]]
    for shape in WindowShape.allCases {
        guard let size = shape.contentSize else { continue }
        for panels in combos {
            let w = LayoutView.panelWidths(size: size, panels: panels)
            let fixed = w.gonio + w.lufs + w.vu
            #expect(fixed <= size.width + 1e-9, "\(shape) \(panels)")
            #expect(w.gonio <= size.height)
            if panels.contains(.scope) { #expect(size.width - fixed > 100, "\(shape) \(panels) scope too narrow") }
        }
    }
}

@MainActor @Test func narrowWindowScalesFixedPanels() {
    let w = LayoutView.panelWidths(size: CGSize(width: 600, height: 540), panels: [.goniometer, .lufs])
    #expect(abs(w.gonio + w.lufs - 600) < 1e-9)
}

@MainActor @Test func lufsSlotIsSlim() {
    let w = LayoutView.panelWidths(size: CGSize(width: 1260, height: 540), panels: [.scope, .lufs])
    #expect(abs(w.lufs - 540 * 0.38) < 1e-9)
}
