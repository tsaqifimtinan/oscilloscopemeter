import Foundation
import Testing
@testable import Scope

@MainActor
private func freshDefaults() -> UserDefaults {
    let name = "ScopeTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor @Test func prefsRoundTrip() {
    let defaults = freshDefaults()
    let a = AppSettings(defaults: defaults)
    a.prefs.keepOnTop = true
    a.prefs.scope.window = 4096
    a.toggle(.goniometer)
    let b = AppSettings(defaults: defaults)
    #expect(b.prefs == a.prefs)
}

@MainActor @Test func prefsMissingKeysFallBackToDefaults() throws {
    let defaults = freshDefaults()
    // Saved by an older build that didn't know about `windowShape` (and had `lockAspect`).
    defaults.set(Data(#"{"keepOnTop": true, "lockAspect": true}"#.utf8), forKey: AppSettings.key)
    let settings = AppSettings(defaults: defaults)
    #expect(settings.prefs.keepOnTop)
    #expect(settings.prefs.windowShape == .ultrawide)
    #expect(settings.prefs.panels == [.scope])
}

@MainActor @Test func hotkeysPickLayoutsAndToggleClean() {
    let settings = AppSettings(defaults: freshDefaults())
    settings.toggle(.goniometer)
    #expect(settings.handleKey("4", isEscape: false, resetLoudness: {}))
    #expect(settings.prefs.panels == [.scope, .vu, .lufs, .goniometer])  // goniometer survives presets
    #expect(settings.handleKey("5", isEscape: false, resetLoudness: {}))
    #expect(settings.prefs.panels == [.vu, .lufs, .goniometer])

    #expect(!settings.handleKey("", isEscape: true, resetLoudness: {}))  // Esc only matters in clean mode
    #expect(settings.handleKey("H", isEscape: false, resetLoudness: {}))
    #expect(settings.clean)
    #expect(settings.handleKey("", isEscape: true, resetLoudness: {}))
    #expect(!settings.clean)

    var resets = 0
    #expect(settings.handleKey("r", isEscape: false, resetLoudness: { resets += 1 }))
    #expect(resets == 1)
    #expect(settings.handleKey("6", isEscape: false, resetLoudness: {}))
    #expect(settings.prefs.panels == [.spectrogram, .goniometer])
    #expect(settings.handleKey("7", isEscape: false, resetLoudness: {}))
    #expect(settings.prefs.panels == [.spectrogram, .scope, .goniometer])
    #expect(!settings.handleKey("8", isEscape: false, resetLoudness: {}))
    var clears = 0
    #expect(settings.handleKey("c", isEscape: false, resetLoudness: {}, clearSpectrogram: { clears += 1 }))
    #expect(clears == 1)
    #expect(!settings.handleKey("x", isEscape: false, resetLoudness: {}))
}

@MainActor @Test func unknownWindowShapeFallsBackWithoutResettingPrefs() {
    let defaults = freshDefaults()
    defaults.set(Data(#"{"keepOnTop": true, "windowShape": "48:9"}"#.utf8), forKey: AppSettings.key)
    let settings = AppSettings(defaults: defaults)
    #expect(settings.prefs.windowShape == .ultrawide)
    #expect(settings.prefs.keepOnTop)
}

@Test func windowShapeSizes() {
    #expect(WindowShape.ultrawide.contentSize == CGSize(width: 1260, height: 540))
    #expect(WindowShape.twoToOne.contentSize == CGSize(width: 1080, height: 540))
    #expect(WindowShape.superUltrawide.contentSize == CGSize(width: 1920, height: 540))
    #expect(WindowShape.hd.contentSize == CGSize(width: 960, height: 540))
    #expect(WindowShape.free.contentSize == nil && WindowShape.free.aspect == nil)
    for shape in WindowShape.allCases {
        guard let size = shape.contentSize, let aspect = shape.aspect else { continue }
        #expect(abs(size.width / size.height - aspect.width / aspect.height) < 1e-9)
    }
}

@MainActor @Test func spectrogramSettingsRoundTrip() {
    let defaults = freshDefaults()
    let a = AppSettings(defaults: defaults)
    a.prefs.spectrogram = SpectrogramSettings()
    a.prefs.spectrogram.fftSize = 8192
    a.prefs.spectrogram.history = 30
    a.prefs.spectrogram.channel = .side
    a.prefs.spectrogram.range = .low
    a.prefs.spectrogram.floor = -100
    a.prefs.spectrogram.ceiling = -5
    a.prefs.spectrogram.tilt = 4.5
    a.prefs.spectrogram.colormap = .viridis
    a.prefs.spectrogram.labels = false
    #expect(AppSettings(defaults: defaults).prefs.spectrogram == a.prefs.spectrogram)
}

@MainActor @Test func unknownSpectrogramValuesFallBackOneByOne() {
    let defaults = freshDefaults()
    let stored = #"{"keepOnTop": true, "spectrogram": {"fftSize": 1000, "history": 7, "channel": "Quad", "#
        + #""range": "1-2 Hz", "floor": -500, "ceiling": -20, "tilt": 9, "colormap": "Jet", "labels": false}}"#
    defaults.set(Data(stored.utf8), forKey: AppSettings.key)
    let s = AppSettings(defaults: defaults)
    var expected = SpectrogramSettings()
    expected.ceiling = -20  // the only valid values survive
    expected.labels = false
    #expect(s.prefs.spectrogram == expected)
    #expect(s.prefs.keepOnTop)  // the rest of the prefs aren't reset
}

@Test func layoutAndPanelRoundTrip() throws {
    for layout in LayoutPreset.allCases { #expect(LayoutPreset(rawValue: layout.rawValue) == layout) }
    let panels = Set(Panel.allCases)
    #expect(try JSONDecoder().decode(Set<Panel>.self, from: JSONEncoder().encode(panels)) == panels)
    #expect(LayoutPreset.allCases.firstIndex(of: .spectrogramScope) == 6)  // key 7
}
