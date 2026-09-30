import SwiftUI

/// Arranges the enabled panels. One TimelineView drives every panel's redraw.
struct LayoutView: View {
    let capture: AudioCapture
    let prefs: Prefs

    var body: some View {
        let background = prefs.background.color
        TimelineView(.animation) { timeline in
            HStack(spacing: 0) {
                if prefs.panels.contains(.scope) {
                    ScopeView(feed: capture.feed, settings: prefs.scope, background: background, date: timeline.date)
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
