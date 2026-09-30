import CoreMedia
import Testing
@testable import Scope

/// Builds a Float32 audio sample buffer; `channels` is one array per channel.
private func makeBuffer(_ channels: [[Float]], interleaved: Bool, rate: Double = 48_000) throws -> CMSampleBuffer {
    let count = channels.count, frames = channels[0].count
    let bytesPerFrame = UInt32(4 * (interleaved ? count : 1))
    var asbd = AudioStreamBasicDescription(
        mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
            | (interleaved ? 0 : kAudioFormatFlagIsNonInterleaved),
        mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
        mChannelsPerFrame: UInt32(count), mBitsPerChannel: 32, mReserved: 0)
    var format: CMAudioFormatDescription?
    try #require(CMAudioFormatDescriptionCreate(
        allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
        magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr)

    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: CMTimeScale(rate)), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
    var buffer: CMSampleBuffer?
    try #require(CMSampleBufferCreate(
        allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
        formatDescription: format, sampleCount: frames, sampleTimingEntryCount: 1,
        sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
        sampleBufferOut: &buffer) == noErr)

    let planes: [[Float]] = interleaved ? [(0..<frames).flatMap { f in channels.map { $0[f] } }] : channels
    let abl = AudioBufferList.allocate(maximumBuffers: planes.count)
    defer { free(abl.unsafeMutablePointer) }
    let storage = planes.map { plane in
        let p = UnsafeMutablePointer<Float>.allocate(capacity: plane.count)
        p.initialize(from: plane, count: plane.count)
        return p
    }
    defer { storage.forEach { $0.deallocate() } }
    for (i, plane) in planes.enumerated() {
        abl[i] = AudioBuffer(
            mNumberChannels: interleaved ? UInt32(count) : 1,
            mDataByteSize: UInt32(plane.count * 4), mData: storage[i])
    }
    let sb = try #require(buffer)
    try #require(CMSampleBufferSetDataBufferFromAudioBufferList(
        sb, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0,
        bufferList: abl.unsafePointer) == noErr)
    return sb
}

private let l: [Float] = (0..<512).map { Float($0) / 512 }
private let r: [Float] = (0..<512).map { -Float($0) / 512 }

private func extracted(_ buffer: CMSampleBuffer) -> ([Float], [Float]) {
    let x = SampleExtractor()
    let n = x.extract(buffer)
    return (Array(UnsafeBufferPointer(start: x.left, count: n)), Array(UnsafeBufferPointer(start: x.right, count: n)))
}

@Test func planarStereo() throws {
    let (outL, outR) = extracted(try makeBuffer([l, r], interleaved: false))
    #expect(outL == l)
    #expect(outR == r)
}

@Test func interleavedStereo() throws {
    let (outL, outR) = extracted(try makeBuffer([l, r], interleaved: true))
    #expect(outL == l)
    #expect(outR == r)
}

@Test func monoDuplicates() throws {
    let (outL, outR) = extracted(try makeBuffer([l], interleaved: true))
    #expect(outL == l)
    #expect(outR == l)
}

@Test func rejectsOtherSampleRates() throws {
    let x = SampleExtractor()
    #expect(x.extract(try makeBuffer([l, r], interleaved: false, rate: 44_100)) == 0)
    #expect(x.rejectedSampleRate == 44_100)
}

@Test func dBFSValues() {
    #expect(abs(dBFS(rms: Float(0.5).squareRoot()) - -3.0103) < 0.001)
    #expect(dBFS(rms: 1) == 0)
    #expect(dBFS(rms: 0) == -120)
}
