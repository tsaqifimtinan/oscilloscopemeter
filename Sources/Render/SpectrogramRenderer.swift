import MetalKit

/// Draws the spectrogram: new columns go into a ring texture at `head`; the shader scrolls by
/// offsetting with `head`, and applies floor/ceiling and the colormap to the whole history.
@MainActor
final class SpectrogramRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commands: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let queue: ColumnQueue
    private var staging: [UInt8]
    private var cursor = ColumnQueue.Cursor()
    private var history: MTLTexture!
    private var lut: MTLTexture
    private var head = 0
    /// Floor and ceiling in dBFS.
    var floor: Float = -90
    var ceiling: Float = -10
    var colormap = Colormap.ice {
        didSet { if colormap != oldValue { upload(colormap) } }
    }
    /// Texture width in columns; changing it clears the picture.
    var width = 1024 {
        didSet { if width != oldValue { makeHistory() } }
    }

    init(queue: ColumnQueue) {
        // ponytail: every Mac that runs macOS 15 has Metal; no fallback renderer.
        device = MTLCreateSystemDefaultDevice()!
        commands = device.makeCommandQueue()!
        pipeline = try! Self.makePipeline(device)
        self.queue = queue
        staging = .init(repeating: 0, count: queue.rows * queue.capacity)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 256, height: 1, mipmapped: false)
        lut = device.makeTexture(descriptor: d)!
        super.init()
        upload(colormap)
        makeHistory()
    }

    /// Compiled from source at launch, so building doesn't need the Metal Toolchain.
    static func makePipeline(_ device: MTLDevice) throws -> MTLRenderPipelineState {
        let library = try device.makeLibrary(source: shader, options: nil)
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "specVert")
        d.fragmentFunction = library.makeFunction(name: "specFrag")
        d.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try device.makeRenderPipelineState(descriptor: d)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = commands.makeCommandBuffer() else { return }
        encode(pass, into: buffer)
        buffer.present(drawable)
        buffer.commit()
    }

    /// Uploads new columns and draws the history into `pass` (tests render offscreen through this).
    func encode(_ pass: MTLRenderPassDescriptor, into buffer: MTLCommandBuffer) {
        drainColumns()
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var params = SIMD3<Float>(Float(head), (floor + 120) / 120, (ceiling + 120) / 120)  // matches `Params`
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(history, index: 0)
        encoder.setFragmentTexture(lut, index: 1)
        encoder.setFragmentBytes(&params, length: 12, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Copies new columns into the ring texture.
    private func drainColumns() {
        let rows = queue.rows
        let (n, _, cleared) = staging.withUnsafeMutableBufferPointer {
            queue.read(cursor: &cursor, into: $0.baseAddress!, max: queue.capacity)
        }
        if cleared { clearHistory() }
        // ponytail: shared texture written while the GPU may still read last frame's; worst case is one
        // frame showing a half-written column. Triple-buffered uploads if that's ever visible.
        staging.withUnsafeBytes { bytes in
            for i in 0..<n {
                history.replace(region: MTLRegionMake2D(head, 0, 1, rows), mipmapLevel: 0,
                                withBytes: bytes.baseAddress! + i * rows, bytesPerRow: 1)
                head = (head + 1) % width
            }
        }
    }

    private func makeHistory() {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: queue.rows,
                                                         mipmapped: false)
        d.storageMode = .shared
        d.usage = .shaderRead
        history = device.makeTexture(descriptor: d)!
        clearHistory()
    }

    private func clearHistory() {
        let zeros = [UInt8](repeating: 0, count: width * queue.rows)
        history.replace(region: MTLRegionMake2D(0, 0, width, queue.rows), mipmapLevel: 0,
                        withBytes: zeros, bytesPerRow: width)
        head = 0
    }

    private func upload(_ map: Colormap) {
        lut.replace(region: MTLRegionMake2D(0, 0, 256, 1), mipmapLevel: 0, withBytes: map.lut, bytesPerRow: 256 * 4)
    }
}

private let shader = """
#include <metal_stdlib>
using namespace metal;

struct VSOut {
    float4 pos [[position]];
    float2 uv;  // (0, 0) top-left, (1, 1) bottom-right
};

// One triangle that covers the viewport.
vertex VSOut specVert(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    VSOut o;
    o.pos = float4(p * 2 - 1, 0, 1);
    o.uv = float2(p.x, 1 - p.y);
    return o;
}

struct Params { float head; float floorN; float ceilN; };  // head in columns; floor/ceil in 0...1 of -120...0 dBFS

fragment float4 specFrag(VSOut in [[stage_in]],
                         texture2d<float> spec [[texture(0)]],  // r8Unorm, columns x rows, row 0 = lowest frequency
                         texture2d<float> lut  [[texture(1)]],  // 256 x 1 colormap
                         constant Params& p    [[buffer(0)]]) {
    constexpr sampler sSpec(filter::linear, address::clamp_to_edge);
    constexpr sampler sLut(filter::linear, address::clamp_to_edge);
    float w = spec.get_width();
    // Oldest column sits at `head`, so the newest (head - 1) ends at the right edge. x snaps to the
    // texel center: no blending between columns, so no seam where newest meets oldest.
    float x = (fmod(floor(in.uv.x * w) + p.head, w) + 0.5) / w;
    float v = spec.sample(sSpec, float2(x, 1.0 - in.uv.y)).r;
    float t = saturate((v - p.floorN) / max(p.ceilN - p.floorN, 1e-4));
    return lut.sample(sLut, float2((t * 255 + 0.5) / 256, 0.5));
}
"""
