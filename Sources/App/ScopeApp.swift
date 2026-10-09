import SwiftUI

@main
struct ScopeApp: App {
    @State private var capture = AudioCapture()
    @State private var settings = AppSettings()
    /// Held for the app's lifetime so rendering and audio processing are never throttled
    /// when the window is in the background or partly covered (e.g. behind OBS).
    private let activity = ProcessInfo.processInfo.beginActivity(
        options: [.userInitiated, .latencyCritical], reason: "Realtime audio visualization")

    var body: some Scene {
        WindowGroup("Scope") {
            ContentView(capture: capture, settings: settings)
        }
        .defaultSize(width: 1260, height: 540)
        .commands {
            CommandGroup(after: .toolbar) { ViewMenuItems(settings: settings, meters: capture.meters) }
        }
    }
}

struct ContentView: View {
    let capture: AudioCapture
    @Bindable var settings: AppSettings
    @State private var keyMonitor: Any?

    var body: some View {
        LayoutView(capture: capture, settings: settings)
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                if !settings.clean { HStack(spacing: 16) { levels; captureControls }.padding(10) }
            }
            .overlay(alignment: .bottom) {
                if !settings.clean && settings.prefs.panels.contains(.scope) { scopeControls }
            }
            .gesture(WindowDragGesture(), isEnabled: settings.clean)
            .allowsWindowActivationEvents(true)
            .contextMenu { ViewMenuItems(settings: settings, meters: capture.meters) }
            .background(WindowAccessor { window in
                settings.chrome.attach(window)
                applyChrome()
            })
            .onChange(of: settings.clean) { applyChrome() }
            .onChange(of: settings.prefs) { applyChrome() }
            .onChange(of: settings.loudnessHeld) { capture.meters.setLoudnessHeld(settings.loudnessHeld) }
            .onAppear { installKeyMonitor() }
            .onDisappear { keyMonitor.map(NSEvent.removeMonitor) }
            .containerBackground(settings.prefs.background.color, for: .window)
            .frame(minWidth: 320, minHeight: 180)
            .preferredColorScheme(.dark)
    }

    private func applyChrome() {
        settings.chrome.apply(clean: settings.clean, prefs: settings.prefs)
    }

    /// App-local keys (only while Scope is focused); plain keys only, so menu shortcuts pass through.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        let meters = capture.meters
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [settings] event in
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let characters = event.charactersIgnoringModifiers ?? ""
            let isEscape = event.keyCode == 53
            let handled = MainActor.assumeIsolated {
                settings.handleKey(characters, isEscape: isEscape, resetLoudness: meters.resetLoudness)
            }
            return handled ? nil : event
        }
    }

    private var levels: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            Text(readout(capture.meters.snapshot, capture.spectrogram.snapshot))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func readout(_ m: MeterSnapshot, _ s: SpectrumSnapshot) -> String {
        let text = String(format: "L %6.1f  R %6.1f dBFS", m.rmsL, m.rmsR)
        #if DEBUG
        return text + "  · overruns \(m.overruns)"
            + String(format: "  · spec %.0f Hz %.1f dB ov %d", s.peakHz, s.peakDB, s.overruns)
        #else
        return text
        #endif
    }

    private var captureControls: some View {
        HStack(spacing: 10) {
            Text(status).font(.caption).foregroundStyle(.secondary)
            switch capture.state {
            case .notGranted:
                Button("Request Access") { capture.requestPermission() }
                Link("Privacy Settings",
                     destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            case .granted, .error:
                Button("Start") { Task { await capture.start() } }
            case .capturing:
                Button("Stop") { Task { await capture.stop() } }
            }
        }
        .disabled(capture.busy)
    }

    private var scopeControls: some View {
        HStack(spacing: 16) {
            Picker("Window", selection: $settings.prefs.scope.window) {
                ForEach(ScopeSettings.windows, id: \.self) { n in
                    Text(String(format: "%d (%.1f ms)", n, Double(n) / 48)).tag(n)
                }
            }
            .fixedSize()
            Slider(value: $settings.prefs.scope.gain, in: 0.25...8) {
                Text(String(format: "Gain %.2f×", settings.prefs.scope.gain)).monospacedDigit()
            }
            Slider(value: $settings.prefs.scope.triggerLevel, in: -1...1) {
                Text(String(format: "Trig %+.2f", settings.prefs.scope.triggerLevel)).monospacedDigit()
            }
            Picker("Edge", selection: $settings.prefs.scope.edge) {
                ForEach(TriggerEdge.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Picker("Mode", selection: $settings.prefs.scope.mode) {
                ForEach(TriggerMode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var status: String {
        switch capture.state {
        case .notGranted: "Screen Recording not granted — relaunch after granting"
        case .granted: "Ready"
        case .capturing: "Capturing"
        case .error(let message): "Error: \(message)"
        }
    }
}
