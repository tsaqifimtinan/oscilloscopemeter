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
    // Saved by an older build that didn't know about `lockAspect`.
    defaults.set(Data(#"{"keepOnTop": true}"#.utf8), forKey: AppSettings.key)
    let settings = AppSettings(defaults: defaults)
    #expect(settings.prefs.keepOnTop)
    #expect(settings.prefs.lockAspect == false)
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
    #expect(!settings.handleKey("6", isEscape: false, resetLoudness: {}))
    #expect(!settings.handleKey("x", isEscape: false, resetLoudness: {}))
}
