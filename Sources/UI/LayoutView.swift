import SwiftUI

// Wide-layout knobs. Aspects are width : height of each panel's slot.
private let lufsAspect: CGFloat = 0.55      // tall and narrow, height-bound
private let lufsMinWidth: CGFloat = 200     // readout text fits
private let vuAspect: CGFloat = 2.4         // reference image
private let vuMaxShare: CGFloat = 0.5       // VU's share of the width left after goniometer/LUFS when the scope shows
private let fixedMaxShare: CGFloat = 0.6    // goniometer + LUFS cap when the scope shows, so it keeps some width
private let stackedBelow: CGFloat = 1.6     // narrower windows use the stacked arrangement

/// Arranges the enabled panels. One TimelineView drives every panel's redraw.
struct LayoutView: View {
    let capture: AudioCapture
    @Bindable var settings: AppSettings

    struct Widths: Equatable {
        var gonio: CGFloat = 0, lufs: CGFloat = 0, vu: CGFloat = 0
    }

    /// Fixed slot widths for the side-by-side layout; the scope (or VU without a scope) takes the rest.
    static func panelWidths(size: CGSize, panels: Set<Panel>) -> Widths {
        let w = size.width, h = size.height
        var out = Widths()
        if panels.contains(.goniometer) { out.gonio = h }  // square
        if panels.contains(.lufs) { out.lufs = max(h * lufsAspect, lufsMinWidth) }
        let fixed = out.gonio + out.lufs, budget = panels.contains(.scope) ? w * fixedMaxShare : w
        if fixed > budget {
            out.gonio *= budget / fixed
            out.lufs *= budget / fixed
        }
        let rest = w - out.gonio - out.lufs
        if panels.contains(.vu) {
            out.vu = panels.contains(.scope) ? min(h * vuAspect, rest * vuMaxShare) : rest
        }
        return out
    }

    var body: some View {
        let prefs = settings.prefs
        let background = prefs.background.color
        // ponytail: 60 Hz cap. SwiftUI's per-frame overhead across all panels is the cost (not DSP);
        // OBS records at ≤60 fps anyway. The Metal renderer (PLAN M4) is the path to 120 Hz for less CPU.
        TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
            let meters = capture.meters.snapshot
            GeometryReader { geo in
                Group {
                    if geo.size.width < geo.size.height * stackedBelow {
                        stacked(prefs: prefs, meters: meters, date: timeline.date)
                    } else {
                        wide(prefs: prefs, meters: meters, date: timeline.date,
                             widths: Self.panelWidths(size: geo.size, panels: prefs.panels))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .background(background)
        }
    }

    /// Side by side: scope (flexible) | VU | goniometer | LUFS.
    private func wide(prefs: Prefs, meters: MeterSnapshot, date: Date, widths: Widths) -> some View {
        HStack(spacing: 0) {
            if prefs.panels.contains(.scope) {
                scope(prefs, date: date)
            }
            if prefs.panels.contains(.vu) {
                vu(prefs, meters: meters).frame(width: widths.vu)
            }
            if prefs.panels.contains(.goniometer) {
                goniometer(prefs, date: date).frame(width: widths.gonio)
            }
            if prefs.panels.contains(.lufs) {
                lufs(prefs, meters: meters).frame(width: widths.lufs)
            }
        }
    }

    /// The pre-M12 arrangement, for Free windows narrower than `stackedBelow`.
    private func stacked(prefs: Prefs, meters: MeterSnapshot, date: Date) -> some View {
        let scope = prefs.panels.contains(.scope), vu = prefs.panels.contains(.vu)
        return HStack(spacing: 0) {
            if scope || vu {
                VStack(spacing: 0) {
                    if scope { self.scope(prefs, date: date) }
                    if vu { self.vu(prefs, meters: meters).frame(maxHeight: scope ? 220 : .infinity) }
                }
            }
            if prefs.panels.contains(.goniometer) {
                goniometer(prefs, date: date).aspectRatio(1, contentMode: .fit)
            }
            if prefs.panels.contains(.lufs) {
                lufs(prefs, meters: meters).frame(width: 230)
            }
        }
    }

    private func scope(_ prefs: Prefs, date: Date) -> some View {
        ScopeView(feed: capture.feed, settings: prefs.scope, background: prefs.background.color, date: date)
    }

    private func vu(_ prefs: Prefs, meters: MeterSnapshot) -> some View {
        VUMeterView(snapshot: meters, reference: prefs.vuReference, mono: prefs.vuMono,
                    background: prefs.background.color)
    }

    private func goniometer(_ prefs: Prefs, date: Date) -> some View {
        GoniometerView(feed: capture.feed, gain: prefs.scope.gain, background: prefs.background.color, date: date)
    }

    private func lufs(_ prefs: Prefs, meters: MeterSnapshot) -> some View {
        LoudnessPanelView(snapshot: meters, target: prefs.lufsTarget, showPeaks: prefs.showPeaks,
                          showButtons: !settings.clean, held: $settings.loudnessHeld,
                          onReset: capture.meters.resetLoudness)
    }
}
