import Accelerate
import Foundation

final class SpectrumAnalyzer {
    let fftSize: Int
    let log2n: vDSP_Length
    let sampleRate: Double
    let bandCount: Int
    let minFreq: Double
    let maxFreq: Double

    private let setup: FFTSetup
    private var window: [Float]
    private var realIn: [Float]
    private var realOut: [Float]
    private var imagOut: [Float]
    private var magnitudes: [Float]

    // Smoothed log-band output
    private(set) var bands: [Float]
    private let smoothing: Float

    init(fftSize: Int, sampleRate: Double, bandCount: Int, minFreq: Double, maxFreq: Double, smoothing: Float) {
        precondition(fftSize > 0 && (fftSize & (fftSize - 1)) == 0, "fftSize must be power of two")
        self.fftSize = fftSize
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.sampleRate = sampleRate
        self.bandCount = bandCount
        self.minFreq = minFreq
        self.maxFreq = maxFreq
        self.smoothing = smoothing
        self.setup = vDSP_create_fftsetup(self.log2n, FFTRadix(kFFTRadix2))!
        self.window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&self.window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.realIn = [Float](repeating: 0, count: fftSize)
        self.realOut = [Float](repeating: 0, count: fftSize / 2)
        self.imagOut = [Float](repeating: 0, count: fftSize / 2)
        self.magnitudes = [Float](repeating: 0, count: fftSize / 2)
        self.bands = [Float](repeating: 0, count: bandCount)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Feed a window of `fftSize` mono samples. Updates `bands` in-place.
    func process(_ samples: UnsafePointer<Float>) {
        vDSP_vmul(samples, 1, window, 1, &realIn, 1, vDSP_Length(fftSize))

        realIn.withUnsafeMutableBufferPointer { inPtr in
            realOut.withUnsafeMutableBufferPointer { rPtr in
                imagOut.withUnsafeMutableBufferPointer { iPtr in
                    var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                    inPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { cPtr in
                        vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
                }
            }
        }

        let nyquist: Double = sampleRate / 2.0
        let nBins: Int = fftSize / 2
        let logMin: Double = log(minFreq)
        let logMax: Double = log(maxFreq)
        let logSpan: Double = logMax - logMin
        let bandCountD: Double = Double(bandCount)
        let nBinsD: Double = Double(nBins)
        let fftSizeF: Float = Float(fftSize)
        for b in 0..<bandCount {
            let bd: Double = Double(b)
            let bd1: Double = Double(b + 1)
            let loHz: Double = exp(logMin + logSpan * bd / bandCountD)
            let hiHz: Double = exp(logMin + logSpan * bd1 / bandCountD)
            let loBinRaw: Int = max(1, Int(loHz / nyquist * nBinsD))
            // loBin must leave room for at least one bin below nBins-1; if a
            // band's lower edge sits at or above Nyquist (config.max_freq_hz
            // ≥ sampleRate/2) it would otherwise collapse to span ≤ 0 and
            // produce NaN downstream.
            let loBin: Int = min(loBinRaw, nBins - 2)
            let hiBin: Int = min(nBins - 1, max(loBin + 1, Int(hiHz / nyquist * nBinsD)))
            var sum: Float = 0
            for k in loBin..<hiBin { sum += magnitudes[k] }
            let span: Int = max(1, hiBin - loBin)
            let avg: Float = sum / Float(span) / fftSizeF
            let db: Float = 20.0 * log10f(max(avg, 1e-6))
            let norm: Float = max(0, min(1, (db + 80.0) / 80.0))
            bands[b] = bands[b] * smoothing + norm * (1 - smoothing)
        }
    }

    /// RMS power of a mono frame, normalized 0..1 (rough).
    static func rms(_ samples: UnsafePointer<Float>, _ count: Int) -> Float {
        var r: Float = 0
        vDSP_rmsqv(samples, 1, &r, vDSP_Length(count))
        return r
    }
}
