import MetalKit
import SwiftUI

/// Persisted spectrogram settings. Floor, ceiling, tilt and colormap restyle the existing history;
/// the rest restart it.
struct SpectrogramSettings: Codable, Equatable {
    static let histories = [5, 10, 20, 30]  // seconds
    static let floorRange: ClosedRange<Float> = -120 ... -40
    static let ceilingRange: ClosedRange<Float> = -70 ... 0
    static let tiltRange: ClosedRange<Float> = 0...6

    var fftSize = 4096
    var history = 10
    var channel = SpectrogramChannel.mix
    var range = FrequencyRange.full
    var floor: Float = -90  // dBFS
    var ceiling: Float = -10
    var tilt: Float = 3  // dB/oct around 1 kHz
    var colormap = Colormap.ice
    var labels = true  // normal mode only; clean mode never shows them

    init() {}

    /// Field by field, so one unknown or out-of-range stored value falls back alone.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T, valid: (T) -> Bool = { _ in true }) -> T {
            (try? c.decode(T.self, forKey: key)).flatMap { valid($0) ? $0 : nil } ?? fallback
        }
        let d = Self()
        fftSize = value(.fftSize, d.fftSize, valid: SpectrogramConfig.fftSizes.contains)
        history = value(.history, d.history, valid: Self.histories.contains)
        channel = value(.channel, d.channel)
        range = value(.range, d.range)
        floor = value(.floor, d.floor, valid: Self.floorRange.contains)
        ceiling = value(.ceiling, d.ceiling, valid: Self.ceilingRange.contains)
        tilt = value(.tilt, d.tilt, valid: Self.tiltRange.contains)
        colormap = value(.colormap, d.colormap)
        labels = value(.labels, d.labels)
    }

    func config(columns: Int) -> SpectrogramConfig {
        SpectrogramConfig(fftSize: fftSize, history: Double(history), channel: channel, range: range, columns: columns)
    }
}

/// The spectrogram panel: an MTKView redrawing at 60 Hz from its own display link.
struct SpectrogramView: NSViewRepresentable {
    let engine: SpectrogramEngine
    let settings: SpectrogramSettings
    /// History texture width: 2048 columns for panels wider than this aspect, else 1024.
    static let wideAspect: CGFloat = 2.5

    @MainActor final class Coordinator {
        let renderer: SpectrogramRenderer
        var aspect: CGFloat = 0
        var sent: SpectrogramConfig?

        init(queue: ColumnQueue) { renderer = SpectrogramRenderer(queue: queue) }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(queue: engine.columns)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = true
        view.layer?.isOpaque = true
        // Same color space as SwiftUI's Color(red:green:blue:), so Ice matches the scope trace.
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.delegate = context.coordinator.renderer
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        sync(context.coordinator)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MTKView, context: Context) -> CGSize? {
        if let w = proposal.width, let h = proposal.height, h > 0 {
            context.coordinator.aspect = w / h
            sync(context.coordinator)
        }
        return nil
    }

    private func sync(_ c: Coordinator) {
        let r = c.renderer
        r.width = c.aspect > Self.wideAspect ? 2048 : 1024
        (r.floor, r.ceiling, r.tilt, r.range, r.colormap) =
            (settings.floor, settings.ceiling, settings.tilt, settings.range, settings.colormap)
        let config = settings.config(columns: r.width)
        if config != c.sent {
            engine.configure(config)
            c.sent = config
        }
    }
}
