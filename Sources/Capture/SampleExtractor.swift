import Accelerate
import CoreMedia

/// Splits an audio `CMSampleBuffer` into contiguous Float32 left/right channels.
/// All memory is preallocated; `extract` does not allocate. Use from a single queue only.
final class SampleExtractor: @unchecked Sendable {
    let capacity: Int
    let left: UnsafeMutablePointer<Float>
    let right: UnsafeMutablePointer<Float>
    private let interleaved: UnsafeMutablePointer<Float>
    private let abl: UnsafeMutableAudioBufferListPointer

    init(capacity: Int = 16_384) {
        self.capacity = capacity
        left = .allocate(capacity: capacity)
        right = .allocate(capacity: capacity)
        interleaved = .allocate(capacity: capacity * 2)
        abl = AudioBufferList.allocate(maximumBuffers: 2)
    }

    deinit {
        left.deallocate()
        right.deallocate()
        interleaved.deallocate()
        free(abl.unsafeMutablePointer)
    }

    /// Fills `left`/`right` and returns the frame count, or 0 if the format is unsupported.
    /// Mono input is duplicated into both channels.
    func extract(_ buffer: CMSampleBuffer) -> Int {
        guard let format = buffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              asbd.mBitsPerChannel == 32
        else { return 0 }
        // ponytail: 1–2 channels only; SCStream is configured for stereo. Surround would need a downmix.
        let channels = Int(asbd.mChannelsPerFrame)
        let frames = min(buffer.numSamples, capacity)
        guard (1...2).contains(channels), frames > 0 else { return 0 }
        let planar = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let bytes = UInt32(frames * MemoryLayout<Float>.size)

        if channels == 2 && !planar {
            abl.count = 1
            abl[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: bytes * 2, mData: interleaved)
        } else {
            abl.count = channels
            abl[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: bytes, mData: left)
            if channels == 2 {
                abl[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: bytes, mData: right)
            }
        }
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            buffer, at: 0, frameCount: Int32(frames), into: abl.unsafeMutablePointer)
        guard status == noErr else { return 0 }

        if channels == 2 && !planar {
            var split = DSPSplitComplex(realp: left, imagp: right)
            interleaved.withMemoryRebound(to: DSPComplex.self, capacity: frames) {
                vDSP_ctoz($0, 2, &split, 1, vDSP_Length(frames))
            }
        } else if channels == 1 {
            right.update(from: left, count: frames)
        }
        return frames
    }
}

/// RMS to dBFS, floored at -120.
func dBFS(rms: Float) -> Float {
    max(20 * log10(rms), -120)
}
