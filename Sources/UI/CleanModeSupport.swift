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

extension WindowShape {
    var menuLabel: String {
        guard let size = contentSize else { return "Free (no aspect lock)" }
        return "\(rawValue)  —  \(Int(size.width)) × \(Int(size.height)) (\(Int(size.width) * 2) × \(Int(size.height) * 2) px)"
    }
}

/// Applies clean mode and window-level prefs to the app's NSWindow.
@MainActor
final class WindowChrome {
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
        // The title bar becomes content space under fullSizeContentView; keep the content size
        // (and so the aspect and OBS pixel size) by resizing the frame around it.
        let content = window.contentRect(forFrameRect: window.frame).size
        if clean && !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
            addedFullSizeContent = true
            setContentSize(content)
        } else if !clean && addedFullSizeContent {
            window.styleMask.remove(.fullSizeContentView)
            addedFullSizeContent = false
            setContentSize(content)
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

        if let aspect = prefs.windowShape.aspect {
            window.contentAspectRatio = aspect
        } else {
            window.contentResizeIncrements = NSSize(width: 1, height: 1)  // clears the aspect lock
        }
        if clean { NSCursor.setHiddenUntilMouseMoves(true) }
    }

    /// Resizes keeping the window's top edge in place.
    func setContentSize(_ size: CGSize) {
        guard let window else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true)
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
        Menu("Layout") {
            ForEach(Array(LayoutPreset.allCases.enumerated()), id: \.element) { i, layout in
                Button("\(layout.rawValue)  (\(i + 1))") { settings.apply(layout) }
            }
        }
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
        Menu("Window Shape") {
            ForEach(WindowShape.allCases, id: \.self) { shape in
                Toggle(shape.menuLabel, isOn: Binding(
                    get: { settings.prefs.windowShape == shape },
                    set: { _ in
                        settings.prefs.windowShape = shape
                        shape.contentSize.map(settings.chrome.setContentSize)
                    }))
            }
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
            Divider()
            Toggle("Pause", isOn: $settings.loudnessHeld)
            Button("Reset  (R)") { meters.resetLoudness() }
        }
    }
}
