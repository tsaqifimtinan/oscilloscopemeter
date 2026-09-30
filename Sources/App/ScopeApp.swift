import SwiftUI

@main
struct ScopeApp: App {
    @State private var capture = AudioCapture()

    var body: some Scene {
        WindowGroup("Scope") {
            ContentView(capture: capture)
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    let capture: AudioCapture

    var body: some View {
        VStack(spacing: 16) {
            Text(status).font(.headline)

            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let (l, r) = capture.levels
                Text(String(format: "L %6.1f dBFS   R %6.1f dBFS", l, r))
                    .font(.system(.title2, design: .monospaced))
            }

            switch capture.state {
            case .notGranted:
                Button("Request Screen Recording Access") { capture.requestPermission() }
                Link("Open Privacy Settings",
                     destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                Text("After granting, quit and relaunch Scope.").font(.caption).foregroundStyle(.secondary)
            case .granted, .error:
                Button("Start Capture") { Task { await capture.start() } }
            case .capturing:
                Button("Stop Capture") { Task { await capture.stop() } }
            }
        }
        .disabled(capture.busy)
        .padding(24)
        .frame(minWidth: 380)
    }

    private var status: String {
        switch capture.state {
        case .notGranted: "Screen Recording permission not granted"
        case .granted: "Ready"
        case .capturing: "Capturing system audio"
        case .error(let message): "Error: \(message)"
        }
    }
}
