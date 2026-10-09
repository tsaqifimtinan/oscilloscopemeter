import Metal
import Testing
@testable import Scope

@MainActor @Test func shaderCompiles() throws {
    _ = try SpectrogramRenderer.makePipeline(MTLCreateSystemDefaultDevice()!)
}

@Test func colormapEndpoints() {
    for map in Colormap.allCases {
        let lut = map.lut
        #expect(lut.count == 256 * 4)
        #expect(lut[3] == 255 && lut[1023] == 255)  // opaque
    }
    let ice = Colormap.ice.lut
    #expect(Array(ice[0..<3]) == [0, 0, 0])
    #expect(Array(ice[1020..<1023]) == [255, 255, 255])
    // Stop 3 of 5 sits at 3/4 = entry 191.25: the scope's blue-gray (0.66, 0.75, 0.92) within rounding.
    let i = 191 * 4
    #expect(abs(Int(ice[i]) - 168) <= 2 && abs(Int(ice[i + 1]) - 191) <= 2 && abs(Int(ice[i + 2]) - 235) <= 2)
}

/// Renders 1 px per column and per row, so pixels map straight onto texels.
@MainActor private func render(_ renderer: SpectrogramRenderer, rows: Int) -> (Int, Int) -> [UInt8] {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: renderer.width, height: rows,
                                                     mipmapped: false)
    d.usage = .renderTarget
    d.storageMode = .shared
    let target = renderer.device.makeTexture(descriptor: d)!
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = target
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    let buffer = renderer.commands.makeCommandBuffer()!
    renderer.encode(pass, into: buffer)
    buffer.commit()
    buffer.waitUntilCompleted()
    var pixels = [UInt8](repeating: 0, count: renderer.width * rows * 4)
    target.getBytes(&pixels, bytesPerRow: renderer.width * 4, from: MTLRegionMake2D(0, 0, renderer.width, rows),
                    mipmapLevel: 0)
    return { x, y in Array(pixels[(y * renderer.width + x) * 4..<(y * renderer.width + x) * 4 + 3]) }  // BGR
}

@MainActor @Test func newestColumnIsAtTheRightAndRowZeroAtTheBottom() {
    let queue = ColumnQueue(rows: 512)
    let renderer = SpectrogramRenderer(queue: queue)
    (renderer.floor, renderer.ceiling) = (-120, 0)  // t = stored value
    var column = [UInt8](repeating: 0, count: 512)
    column[290] = 255
    for _ in 0..<10 { queue.push(column) }
    column[290] = 0
    column[0] = 255
    queue.push(column)  // newest: only the lowest row lit
    let pixel = render(renderer, rows: 512)
    let white: [UInt8] = [255, 255, 255], black: [UInt8] = [0, 0, 0]
    #expect(pixel(1023, 511) == white)  // newest column, bottom row
    #expect(pixel(1023, 511 - 290) == black)
    #expect(pixel(1022, 511 - 290) == white && pixel(1013, 511 - 290) == white)
    #expect(pixel(1012, 511 - 290) == black)  // older than the 11 pushed columns: still empty
    #expect(pixel(1022, 511 - 289) == black)

    queue.clear()
    #expect(render(renderer, rows: 512)(1022, 511 - 290) == black)  // clear wipes the picture
}
