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
