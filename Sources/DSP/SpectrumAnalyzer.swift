import Accelerate

/// One FFT frame to a dBFS spectrum. All buffers are preallocated; `process` doesn't allocate.
final class SpectrumAnalyzer {
    let n: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: UnsafeMutablePointer<Float>
    private let windowed: UnsafeMutablePointer<Float>
    private let re: UnsafeMutablePointer<Float>
    private let im: UnsafeMutablePointer<Float>
    private let power: UnsafeMutablePointer<Float>
    /// 20·log10(n · coherentGain): vDSP_fft_zrip returns 2× the textbook DFT, so a sine of
    /// amplitude A at a bin center gives |X| = A · n · coherentGain.
    private let normDB: Float

    init(fftSize n: Int) {
        precondition(n >= 16 && n & (n - 1) == 0)
        self.n = n
        log2n = vDSP_Length(n.trailingZeroBitCount)
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = .allocate(capacity: n)
        windowed = .allocate(capacity: n)
        re = .allocate(capacity: n / 2)
        im = .allocate(capacity: n / 2)
        power = .allocate(capacity: n / 2)
        vDSP_hann_window(window, vDSP_Length(n), Int32(vDSP_HANN_DENORM))
        var sum: Float = 0
        vDSP_sve(window, 1, &sum, vDSP_Length(n))  // actual window sum, not an assumed n/2
        normDB = 20 * log10(sum)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        for p in [window, windowed, re, im, power] { p.deallocate() }
    }

    /// input: n time-domain samples. dbOut: n/2 bins in dBFS. Bin 0 packs DC and Nyquist: ignore it.
    func process(_ input: UnsafePointer<Float>, dbOut: UnsafeMutablePointer<Float>) {
        let half = vDSP_Length(n / 2)
        vDSP_vmul(input, 1, window, 1, windowed, 1, vDSP_Length(n))
        var split = DSPSplitComplex(realp: re, imagp: im)
        windowed.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
            vDSP_ctoz($0, 2, &split, 1, half)
        }
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
        vDSP_zvmags(&split, 1, power, 1, half)
        var tiny: Float = 1e-12  // silence never gives -inf
        vDSP_vthr(power, 1, &tiny, power, 1, half)
        var one: Float = 1
        vDSP_vdbcon(power, 1, &one, dbOut, 1, half, 0)
        var minusNorm = -normDB
        vDSP_vsadd(dbOut, 1, &minusNorm, dbOut, 1, half)
    }
}
