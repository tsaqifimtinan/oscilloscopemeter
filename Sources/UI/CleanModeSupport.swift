import AppKit
import SwiftUI

extension BackgroundMode {
    var color: Color {
        switch self {
        case .black: .black
        case .chroma: Color(red: 0, green: 1, blue: 0)  // #00FF00
        case .transparent: .clear
        }
    }
}

/// Applies clean mode and window-level prefs to the app's NSWindow.
@MainActor
final class WindowChrome {
    static let sizePresets: [(label: String, size: CGSize)] = [
        ("960 × 540 (1080p on Retina)", CGSize(width: 960, height: 540)),
        ("640 × 360", CGSize(width: 640, height: 360)),
        ("1280 × 720", CGSize(width: 1280, height: 720)),
    ]

    private weak var window: NSWindow?
    private var addedFullSizeContent = false

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.setFrameAutosaveName("ScopeMainWindow")  // persists size and position
    }

    /// Idempotent; call whenever `clean` or `prefs` change.
    func apply(clean: Bool, prefs: Prefs) {
        guard let window else { return }
        window.titleVisibility = clean ? .hidden : .visible
        window.titlebarAppearsTransparent = clean
        if clean && !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
            addedFullSizeContent = true
        } else if !clean && addedFullSizeContent {
            window.styleMask.remove(.fullSizeContentView)
            addedFullSizeContent = false
        }
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = clean
        }
        window.isMovableByWindowBackground = clean
        window.hasShadow = !clean
        window.level = prefs.keepOnTop ? .floating : .normal

        let transparent = prefs.background == .transparent
        window.isOpaque = !transparent
        window.backgroundColor = transparent ? .clear : .black

        if prefs.lockAspect {
            window.contentAspectRatio = NSSize(width: 16, height: 9)
        } else {
            window.contentResizeIncrements = NSSize(width: 1, height: 1)  // clears the aspect lock
        }
        if clean { NSCursor.setHiddenUntilMouseMoves(true) }
    }

    func setContentSize(_ size: CGSize) {
        window?.setContentSize(size)
    }
}

/// Reports the NSWindow hosting this view.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReportingView: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}

/// View-menu items, also used as the right-click menu so they stay reachable in clean mode.
struct ViewMenuItems: View {
    @Bindable var settings: AppSettings
    let meters: MeterEngine

    var body: some View {
        Toggle("Clean Mode", isOn: $settings.clean)
            .keyboardShortcut("h", modifiers: [.command, .shift])
        Menu("Panels") {
            ForEach(Panel.allCases, id: \.self) { panel in
                Toggle(panel.rawValue, isOn: Binding(
                    get: { settings.prefs.panels.contains(panel) },
                    set: { _ in settings.toggle(panel) }))
            }
        }
        Picker("Background", selection: $settings.prefs.background) {
            ForEach(BackgroundMode.allCases, id: \.self) { Text($0.rawValue) }
        }
        Menu("Window Size") {
            ForEach(WindowChrome.sizePresets, id: \.label) { preset in
                Button(preset.label) { settings.chrome.setContentSize(preset.size) }
            }
            Divider()
            Toggle("Lock Aspect 16:9", isOn: $settings.prefs.lockAspect)
        }
        Toggle("Keep on Top", isOn: $settings.prefs.keepOnTop)
        Divider()
        Menu("VU Meter") {
            Picker("Reference", selection: $settings.prefs.vuReference) {
                Text("0 VU = −18 dBFS").tag(Float(-18))
                Text("0 VU = −20 dBFS (EBU)").tag(Float(-20))
                Text("0 VU = −14 dBFS").tag(Float(-14))
            }
            Toggle("Mono Sum", isOn: $settings.prefs.vuMono)
        }
        Menu("Loudness") {
            Picker("Target", selection: $settings.prefs.lufsTarget) {
                Text("−23 LUFS (EBU R128)").tag(-23.0)
                Text("−24 LUFS (ATSC A/85)").tag(-24.0)
                Text("−16 LUFS").tag(-16.0)
                Text("−14 LUFS (streaming)").tag(-14.0)
            }
            Toggle("Show Peaks", isOn: $settings.prefs.showPeaks)
            Divider()
            Toggle("Pause", isOn: $settings.loudnessHeld)
            Button("Reset") { meters.resetLoudness() }
        }
    }
}
