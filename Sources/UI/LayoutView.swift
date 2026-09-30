import SwiftUI

/// Arranges the enabled panels. One TimelineView drives every panel's redraw.
struct LayoutView: View {
    let capture: AudioCapture
    @Bindable var settings: AppSettings

    var body: some View {
        let prefs = settings.prefs
        let background = prefs.background.color
        // ponytail: 60 Hz cap. SwiftUI's per-frame overhead across all panels is the cost (not DSP);
        // OBS records at ≤60 fps anyway. The Metal renderer (PLAN M4) is the path to 120 Hz for less CPU.
        TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
            let meters = capture.meters.snapshot
            let scope = prefs.panels.contains(.scope), vu = prefs.panels.contains(.vu)
            HStack(spacing: 0) {
                if scope || vu {
                    VStack(spacing: 0) {
                        if scope {
                            ScopeView(feed: capture.feed, settings: prefs.scope, background: background, date: timeline.date)
                        }
                        if vu {
                            VUMeterView(snapshot: meters, reference: prefs.vuReference, mono: prefs.vuMono,
                                        background: background)
                                .frame(maxHeight: scope ? 220 : .infinity)
                        }
                    }
                }
                if prefs.panels.contains(.goniometer) {
                    GoniometerView(feed: capture.feed, gain: prefs.scope.gain, background: background, date: timeline.date)
                        .aspectRatio(1, contentMode: .fit)
                }
                if prefs.panels.contains(.lufs) {
                    LoudnessPanelView(snapshot: meters, target: prefs.lufsTarget, showPeaks: prefs.showPeaks,
                                      showButtons: !settings.clean, held: $settings.loudnessHeld,
                                      onReset: capture.meters.resetLoudness)
                        .frame(width: 230)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
        }
    }
}
