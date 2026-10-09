import MetalKit
import SwiftUI

/// The spectrogram panel: an MTKView redrawing at 60 Hz from its own display link.
struct SpectrogramView: NSViewRepresentable {
    let engine: SpectrogramEngine
    /// History texture width: 2048 columns for windows wider than this aspect, else 1024.
    static let wideAspect: CGFloat = 2.5

    func makeCoordinator() -> SpectrogramRenderer {
        SpectrogramRenderer(queue: engine.columns)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = true
        view.layer?.isOpaque = true
        // Same color space as SwiftUI's Color(red:green:blue:), so Ice matches the scope trace.
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MTKView, context: Context) -> CGSize? {
        if let w = proposal.width, let h = proposal.height, h > 0 {
            let columns = w / h > Self.wideAspect ? 2048 : 1024
            let renderer = context.coordinator
            if renderer.width != columns {
                renderer.width = columns
                engine.configure(SpectrogramConfig(columns: columns))
            }
        }
        return nil
    }
}
