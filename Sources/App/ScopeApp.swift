import SwiftUI

@main
struct ScopeApp: App {
    @State private var capture = AudioCapture()

    var body: some Scene {
        WindowGroup("Scope") {
            ContentView(capture: capture)
        }
        .defaultSize(width: 900, height: 360)
    }
}

struct ContentView: View {
    let capture: AudioCapture
    @State private var settings = ScopeSettings()

    var body: some View {
        ScopeView(ring: capture.ring, settings: settings)
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) { levels.padding(10) }
            .overlay(alignment: .topTrailing) { captureControls.padding(10) }
            .overlay(alignment: .bottom) { scopeControls }
            .frame(minWidth: 640, minHeight: 240)
            .preferredColorScheme(.dark)
    }

    private var levels: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let (l, r) = capture.levels
            Text(String(format: "L %6.1f  R %6.1f dBFS", l, r))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
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
            Picker("Window", selection: $settings.window) {
                ForEach(ScopeSettings.windows, id: \.self) { n in
                    Text(String(format: "%d (%.1f ms)", n, Double(n) / 48)).tag(n)
                }
            }
            .fixedSize()
            Slider(value: $settings.gain, in: 0.25...8) {
                Text(String(format: "Gain %.2f×", settings.gain)).monospacedDigit()
            }
            Slider(value: $settings.triggerLevel, in: -1...1) {
                Text(String(format: "Trig %+.2f", settings.triggerLevel)).monospacedDigit()
            }
            Picker("Edge", selection: $settings.edge) {
                ForEach(TriggerEdge.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Picker("Mode", selection: $settings.mode) {
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
