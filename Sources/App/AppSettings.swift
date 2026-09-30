import Foundation
import Observation

enum Panel: String, Codable, CaseIterable {
    case scope = "Scope", goniometer = "Goniometer", vu = "VU", lufs = "LUFS"
}

/// Layout presets set the panel toggles; the goniometer toggle is left as it is.
enum LayoutPreset: String, CaseIterable {
    case scope = "Scope Only", scopeVU = "Scope + VU", scopeLUFS = "Scope + LUFS",
         scopeVULUFS = "Scope + VU + LUFS", meters = "Meters Only"

    var panels: Set<Panel> {
        switch self {
        case .scope: [.scope]
        case .scopeVU: [.scope, .vu]
        case .scopeLUFS: [.scope, .lufs]
        case .scopeVULUFS: [.scope, .vu, .lufs]
        case .meters: [.vu, .lufs]
        }
    }
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
    var lufsTarget = -23.0
    var showPeaks = false
}

/// Shared UI state. `prefs` saves itself to UserDefaults on every change.
@MainActor @Observable
final class AppSettings {
    static let key = "prefs"

    var clean = false
    /// Loudness hold (Pause); not persisted.
    var loudnessHeld = false
    var prefs: Prefs {
        didSet { if prefs != oldValue { save() } }
    }
    @ObservationIgnored let chrome = WindowChrome()
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        prefs = Self.load(from: defaults)
    }

    func apply(_ layout: LayoutPreset) {
        prefs.panels = layout.panels.union(prefs.panels.intersection([.goniometer]))
    }

    /// App-local hotkeys: Esc exits clean mode, H toggles it, 1–5 pick a layout, R resets loudness.
    /// Returns whether the key was handled.
    func handleKey(_ characters: String, isEscape: Bool, resetLoudness: () -> Void) -> Bool {
        if isEscape {
            guard clean else { return false }
            clean = false
            return true
        }
        switch characters.lowercased() {
        case "h": clean.toggle()
        case "r": resetLoudness()
        case let key where Int(key).map((1...5).contains) == true:
            apply(LayoutPreset.allCases[Int(key)! - 1])
        default: return false
        }
        return true
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
