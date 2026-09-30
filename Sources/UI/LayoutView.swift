import SwiftUI

/// Arranges the enabled panels. One TimelineView drives every panel's redraw.
struct LayoutView: View {
    let capture: AudioCapture
    let prefs: Prefs

    var body: some View {
        let background = prefs.background.color
        TimelineView(.animation) { timeline in
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
        }
    }
}
