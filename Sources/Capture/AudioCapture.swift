import Accelerate
import Observation
import ScreenCaptureKit
import Synchronization

/// Owns the SCStream and exposes capture state to the UI.
@MainActor @Observable
final class AudioCapture {
    enum State: Equatable {
        case notGranted, granted, capturing
        case error(String)
    }

    private(set) var state: State
    private(set) var busy = false
    /// Mono mix of the captured audio; persists across start/stop.
    let ring = SampleRing()
    private var stream: SCStream?
    private var output: StreamOutput?

    init() {
        state = CGPreflightScreenCaptureAccess() ? .granted : .notGranted
    }

    /// Latest (left, right) RMS in dBFS.
    var levels: (Float, Float) { output?.levels() ?? (-120, -120) }

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

            let output = StreamOutput(ring: ring) { [weak self] message in
                Task { @MainActor in self?.didStop(message) }
            }
            let stream = SCStream(
                filter: SCContentFilter(display: display, excludingWindows: []),
                configuration: config, delegate: output)
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
            try await stream.startCapture()
            self.stream = stream
            self.output = output
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
        try? await stream.stopCapture()
        state = .granted
    }

    private func didStop(_ message: String) {
        stream = nil
        output = nil
        state = .error(message)
    }

    enum CaptureError: LocalizedError {
        case noDisplay
        var errorDescription: String? { "No display available to capture." }
    }
}

/// Receives sample buffers on `queue`. Mutable state is touched only on `queue`;
/// the UI reads levels through atomics.
final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "scope.capture", qos: .userInteractive)
    private let onStop: @Sendable (String) -> Void
    private let extractor = SampleExtractor()
    private let ring: SampleRing

    // ponytail: plain 100 ms RMS for the readout; proper meters (ballistics, peak hold) are M5.
    private static let window = 4_800  // 100 ms @ 48 kHz
    private var sumL: Float = 0
    private var sumR: Float = 0
    private var count = 0
    private let packedLevels = Atomic<UInt64>(0)  // L/R dBFS float bits
    private let publishedAt = Atomic<UInt64>(0)   // uptime ns

    init(ring: SampleRing, onStop: @escaping @Sendable (String) -> Void) {
        self.ring = ring
        self.onStop = onStop
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        let n = extractor.extract(buffer)
        guard n > 0 else { return }
        var l: Float = 0, r: Float = 0
        vDSP_svesq(extractor.left, 1, &l, vDSP_Length(n))
        vDSP_svesq(extractor.right, 1, &r, vDSP_Length(n))

        // Mono mix in place (levels above already used the separate channels).
        var half: Float = 0.5
        vDSP_vasm(extractor.left, 1, extractor.right, 1, &half, extractor.left, 1, vDSP_Length(n))
        ring.write(extractor.left, count: n)

        sumL += l
        sumR += r
        count += n
        guard count >= Self.window else { return }
        let dl = dBFS(rms: (sumL / Float(count)).squareRoot())
        let dr = dBFS(rms: (sumR / Float(count)).squareRoot())
        packedLevels.store(UInt64(dl.bitPattern) << 32 | UInt64(dr.bitPattern), ordering: .relaxed)
        publishedAt.store(DispatchTime.now().uptimeNanoseconds, ordering: .relaxed)
        sumL = 0
        sumR = 0
        count = 0
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onStop(error.localizedDescription)
    }

    /// (left, right) dBFS; reads as silence if no audio arrived recently.
    func levels() -> (Float, Float) {
        let age = DispatchTime.now().uptimeNanoseconds &- publishedAt.load(ordering: .relaxed)
        guard age < 300_000_000 else { return (-120, -120) }
        let p = packedLevels.load(ordering: .relaxed)
        return (Float(bitPattern: UInt32(p >> 32)), Float(bitPattern: UInt32(truncatingIfNeeded: p)))
    }
}
