import Observation
import ScreenCaptureKit

/// Owns the SCStream and exposes capture state to the UI.
@MainActor @Observable
final class AudioCapture {
    enum State: Equatable {
        case notGranted, granted, capturing
        case error(String)
    }

    private(set) var state: State
    private(set) var busy = false
    /// Captured stereo audio; persists across start/stop.
    let feed = StereoFeed()
    let meters: MeterEngine
    let spectrogram: SpectrogramEngine
    private var stream: SCStream?
    private var output: StreamOutput?

    init() {
        state = CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        meters = MeterEngine(feed: feed)
        spectrogram = SpectrogramEngine(feed: feed)
    }

    func requestPermission() {
        // Shows the system prompt once; the grant only takes effect after relaunch.
        if CGRequestScreenCaptureAccess() { state = .granted }
    }

    func start() async {
        guard !busy, stream == nil else { return }
        busy = true
        defer { busy = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first
            else { throw CaptureError.noDisplay }

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
            // SCStream needs a video target even for audio-only; keep it as cheap as possible.
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let output = StreamOutput(feed: feed) { [weak self] message in
                Task { @MainActor in await self?.didStop(message) }
            }
            let stream = SCStream(
                filter: SCContentFilter(display: display, excludingWindows: []),
                configuration: config, delegate: output)
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
            try await stream.startCapture()
            self.stream = stream
            self.output = output
            meters.start()
            spectrogram.start()
            state = .capturing
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func stop() async {
        guard !busy, let stream else { return }
        busy = true
        defer { busy = false }
        self.stream = nil
        output = nil
        meters.stop()
        spectrogram.stop()
        try? await stream.stopCapture()
        state = .granted
    }

    private func didStop(_ message: String) async {
        let stream = self.stream
        self.stream = nil
        output = nil
        meters.stop()
        spectrogram.stop()
        state = .error(message)
        try? await stream?.stopCapture()  // no-op if the stream already stopped itself
    }

    enum CaptureError: LocalizedError {
        case noDisplay
        var errorDescription: String? { "No display available to capture." }
    }
}

/// Receives sample buffers on `queue` and copies them into the feed. Nothing else happens here:
/// no allocation, no logging, no analysis (apart from the one-time unsupported-rate error).
final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "scope.capture", qos: .userInteractive)
    private let onStop: @Sendable (String) -> Void
    private let extractor = SampleExtractor()  // touched only on `queue`
    private let feed: StereoFeed
    private var reportedRate = false  // touched only on `queue`

    init(feed: StereoFeed, onStop: @escaping @Sendable (String) -> Void) {
        self.feed = feed
        self.onStop = onStop
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        let n = extractor.extract(buffer)
        if n == 0, let rate = extractor.rejectedSampleRate, !reportedRate {
            // Error path, once: never silently run 48 kHz loudness coefficients on another rate.
            reportedRate = true
            onStop("Unsupported sample rate \(Int(rate)) Hz; Scope needs 48 kHz.")
        }
        guard n > 0 else { return }
        feed.write(l: extractor.left, r: extractor.right, count: n)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onStop(error.localizedDescription)
    }
}
