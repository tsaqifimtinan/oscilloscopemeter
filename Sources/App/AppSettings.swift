import Foundation
import Observation

enum Panel: String, Codable, CaseIterable {
    case scope = "Scope", goniometer = "Goniometer", vu = "VU"
}

enum BackgroundMode: String, Codable, CaseIterable {
    case black = "Black", chroma = "Chroma Green", transparent = "Transparent (experimental)"
}

/// Everything that persists across launches.
struct Prefs: Codable, Equatable {
    var scope = ScopeSettings()
    var panels: Set<Panel> = [.scope]
    var background = BackgroundMode.black
    var keepOnTop = false
    var lockAspect = false
    var vuReference: Float = -18  // dBFS RMS that reads 0 VU
    var vuMono = false
}

/// Shared UI state. `prefs` saves itself to UserDefaults on every change.
@MainActor @Observable
final class AppSettings {
    static let key = "prefs"

    var clean = false
    var prefs: Prefs {
        didSet { if prefs != oldValue { save() } }
    }
    @ObservationIgnored let chrome = WindowChrome()
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        prefs = Self.load(from: defaults)
    }

    func toggle(_ panel: Panel) {
        if prefs.panels.contains(panel) { prefs.panels.remove(panel) } else { prefs.panels.insert(panel) }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(prefs), forKey: Self.key)
    }

    /// Stored top-level keys are merged over the defaults, so adding a field later doesn't wipe the rest.
    private static func load(from defaults: UserDefaults) -> Prefs {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fallback = try? JSONEncoder().encode(Prefs()),
              var merged = try? JSONSerialization.jsonObject(with: fallback) as? [String: Any]
        else { return Prefs() }
        merged.merge(stored) { $1 }
        guard let json = try? JSONSerialization.data(withJSONObject: merged),
              let prefs = try? JSONDecoder().decode(Prefs.self, from: json)
        else { return Prefs() }
        return prefs
    }
}
