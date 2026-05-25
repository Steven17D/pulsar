import AudioToolbox
import Darwin
import Foundation
import os
import OSLog
import Synchronization

final class AudioEngine: @unchecked Sendable {
    private let log = Logger(subsystem: "io.pulsar.audio", category: "AudioEngine")
    private let renderState: RenderState
    private let publishLive: @Sendable (LiveFrame, Double) -> Void
    private let cfg: Config
    private let tap = SystemAudioTap()

    // SPSC ring. Writer (CoreAudio IO thread) is the sole mutator of `ring`
    // and `writeIndex`; reader (render thread) is the sole mutator of
    // `readIndex`. Indices are monotonically increasing UInt64s; slot lookup
    // uses `& mask` since `ringCapacity` is a power of two.
    private let ring: UnsafeMutableBufferPointer<Float>
    private let writeIndex = Atomic<UInt64>(0)
    private let readIndex = Atomic<UInt64>(0)
    private let ringCapacity: Int
    private let ringMask: UInt64

    private var senders: [DDPSender] = []
    private var mappers: [Mapper] = []

    private var thread: Thread?
    private var shouldRun: Bool = true

    init(config: Config, renderState: RenderState, publishLive: @escaping @Sendable (LiveFrame, Double) -> Void) {
        self.cfg = config
        self.renderState = renderState
        self.publishLive = publishLive
        let cap = Self.nextPow2(max(config.fft_size * 4, 16384))
        self.ringCapacity = cap
        self.ringMask = UInt64(cap - 1)
        let buf = UnsafeMutableBufferPointer<Float>.allocate(capacity: cap)
        buf.initialize(repeating: 0)
        self.ring = buf
        let view = renderState.snapshot()
        for dev in view.devices {
            senders.append(DDPSender(host: dev.ip, rgbw: dev.rgbw, queueLabel: "ddp.\(dev.name)"))
            mappers.append(Mapper(totalPixels: dev.pixelCount, rgbw: dev.rgbw, effect: view.effect, segments: dev.segments))
        }
    }

    deinit {
        ring.deinitialize()
        ring.deallocate()
    }

    private static func nextPow2(_ n: Int) -> Int {
        var v = 1
        while v < n { v <<= 1 }
        return v
    }

    func start() throws {
        try tap.start { [weak self] ptr, frameCount, channels in
            guard let self else { return }
            // RT context: no allocations, no locks. SPSC single-writer path.
            var w = self.writeIndex.load(ordering: .relaxed)
            let invCh = 1 / Float(max(channels, 1))
            let mask = self.ringMask
            for i in 0..<frameCount {
                var s: Float = 0
                let base = i * channels
                for c in 0..<channels { s += ptr[base + c] }
                self.ring[Int(w & mask)] = s * invCh
                w &+= 1
            }
            self.writeIndex.store(w, ordering: .releasing)
        }

        var waited = 0
        while tap.sampleRate <= 0 && waited < 50 {
            Thread.sleep(forTimeInterval: 0.02); waited += 1
        }

        let t = Thread { [weak self] in self?.run() }
        t.qualityOfService = .userInitiated
        t.name = "pulsar.render"
        self.thread = t
        t.start()
    }

    func stop() {
        shouldRun = false
        tap.stop()
    }

    private func run() {
        let sampleRate = tap.sampleRate > 0 ? tap.sampleRate : 48000
        log.info("render loop running sampleRate=\(sampleRate)")

        let analyzer = SpectrumAnalyzer(
            fftSize: cfg.fft_size,
            sampleRate: sampleRate,
            bandCount: cfg.band_count,
            minFreq: cfg.min_freq_hz,
            maxFreq: cfg.max_freq_hz,
            smoothing: cfg.smoothing
        )

        let frameInterval = 1.0 / Double(cfg.fps)
        var window = [Float](repeating: 0, count: cfg.fft_size)
        let dt = Float(frameInterval)

        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let nanosPerTick = Double(timebase.numer) / Double(timebase.denom)
        func monotonicSeconds() -> Double {
            Double(mach_absolute_time()) * nanosPerTick / 1.0e9
        }

        var lastTick = monotonicSeconds()
        var lastAliveCheck = monotonicSeconds()
        var aggregateAlive = true
        var pixelBytes = [UInt8]()
        var wasEnabledPerDevice = [Bool](repeating: true, count: mappers.count)
        var masterWasEnabled = true
        var wasReactiveSilent = false
        let zeroBands = [Float](repeating: 0, count: cfg.band_count)
        let n = cfg.fft_size

        var featureBeatDetector = BeatDetector()
        var beatPulse: Float = 0
        let beatDecayPerSec: Float = 2.5

        while shouldRun {
            let now = monotonicSeconds()
            let sleep = frameInterval - (now - lastTick)
            if sleep > 0 { Thread.sleep(forTimeInterval: sleep) }
            lastTick = monotonicSeconds()

            let w = writeIndex.load(ordering: .acquiring)
            let r = readIndex.load(ordering: .relaxed)
            let haveWindow = (w &- r) >= UInt64(n)
            if haveWindow {
                let start = w &- UInt64(n)
                let mask = ringMask
                for i in 0..<n {
                    window[i] = ring[Int((start &+ UInt64(i)) & mask)]
                }
                readIndex.store(w, ordering: .releasing)
            }

            var powerOut: Float = 0
            if haveWindow {
                window.withUnsafeBufferPointer { wPtr in
                    analyzer.process(wPtr.baseAddress!)
                }
                let power = window.withUnsafeBufferPointer { SpectrumAnalyzer.rms($0.baseAddress!, $0.count) }
                powerOut = power
            }

            // Audio features for reactive sliders. Bass/treble are mean
            // band magnitudes over the lowest / highest quartile; beat is
            // a 1.0 spike on detected onset that decays exponentially so
            // a slider tied to it gets a snappy pulse not a step.
            let bands = haveWindow ? analyzer.bands : zeroBands
            let quarter = max(1, bands.count / 4)
            var bassSum: Float = 0
            for i in 0..<quarter { bassSum += bands[i] }
            let bassOut = min(1, bassSum / Float(quarter) * 1.5)
            var trebleSum: Float = 0
            for i in (bands.count - quarter)..<bands.count { trebleSum += bands[i] }
            let trebleOut = min(1, trebleSum / Float(quarter) * 1.5)
            beatPulse *= expf(-dt * beatDecayPerSec)
            if featureBeatDetector.update(power: powerOut, dt: dt) {
                beatPulse = 1
            }
            let beatOut = beatPulse

            let view = renderState.snapshot()
            let masterOn = view.enabled
            let effectIsAmbient = Mapper.isAmbient(view.effect)
            let reactiveSilent = !effectIsAmbient && powerOut < 0.001

            if masterOn != masterWasEnabled, !masterOn {
                for i in 0..<mappers.count {
                    mappers[i].writeBlack(into: &pixelBytes)
                    senders[i].send(pixels: pixelBytes)
                }
            }
            masterWasEnabled = masterOn

            func aspectSignal(_ a: AudioAspect) -> Float {
                switch a {
                case .power:  return min(1, powerOut * 4)
                case .bass:   return bassOut
                case .treble: return trebleOut
                case .beat:   return beatOut
                }
            }
            // Drive base × (floor + (1-floor) × signal). The floor stops speed
            // and intensity from collapsing to zero on silence so effects keep
            // moving between beats; brightness has no floor so a quiet room is
            // visibly dark.
            func driven(_ base: Float, signal: Float, floor: Float) -> Float {
                return base * (floor + (1 - floor) * signal)
            }
            let effBrightness = view.brightnessReactive
                ? driven(view.brightness, signal: aspectSignal(view.brightnessAspect), floor: 0.0)
                : view.brightness
            let effSpeed = view.speedReactive
                ? max(0.05, driven(view.speed, signal: aspectSignal(view.speedAspect), floor: 0.25))
                : view.speed
            let effIntensity = view.intensityReactive
                ? driven(view.intensity, signal: aspectSignal(view.intensityAspect), floor: 0.20)
                : view.intensity

            // Ambient effects (plasma, etc.) read `power` to modulate phase rate.
            // When the user has every reactivity toggle off they expect a calm
            // non-pulsing ambient — gate audio power going to ambient renderers
            // by whether any reactivity toggle is on.
            let anyReactive = view.brightnessReactive || view.speedReactive || view.intensityReactive
            let effPower = (Mapper.isAmbient(view.effect) && !anyReactive) ? 0 : powerOut

            for i in 0..<mappers.count {
                let dev = i < view.devices.count ? view.devices[i] : nil
                let devOn = dev?.enabled ?? true
                mappers[i].effect = view.effect
                mappers[i].palette = view.palette
                mappers[i].speed = effSpeed
                mappers[i].intensity = effIntensity
                mappers[i].brightness = effBrightness * (dev?.brightness ?? 1.0)
                mappers[i].minLoad = dev?.minLoad ?? 0
                if let segs = dev?.segments {
                    mappers[i].updateSegments(segs)
                }

                let active = masterOn && devOn
                if !active {
                    if wasEnabledPerDevice[i] {
                        mappers[i].writeBlack(into: &pixelBytes)
                        senders[i].send(pixels: pixelBytes)
                        wasEnabledPerDevice[i] = false
                    }
                    continue
                }
                wasEnabledPerDevice[i] = true
                if reactiveSilent {
                    if !wasReactiveSilent {
                        let idlePurple = Pixel(r: 88, g: 0, b: 180, w: 0)
                        mappers[i].writeSolid(idlePurple, into: &pixelBytes)
                        senders[i].send(pixels: pixelBytes)
                    }
                    continue
                }
                mappers[i].render(bands: bands, power: effPower, dt: dt)
                mappers[i].serialize(into: &pixelBytes)
                senders[i].send(pixels: pixelBytes)
            }
            wasReactiveSilent = reactiveSilent

            let nowMono = monotonicSeconds()
            if nowMono - lastAliveCheck > 1.0 {
                lastAliveCheck = nowMono
                aggregateAlive = tap.aggregateIsAlive()
                if !aggregateAlive {
                    log.error("aggregate device not alive — exiting for launchd respawn")
                    DispatchQueue.main.async { exit(1) }
                    return
                }
            }

            let frame = LiveFrame(
                spectrum: analyzer.bands,
                power: powerOut,
                bass: bassOut,
                treble: trebleOut,
                beat: beatOut,
                lastFrameAgo: 0,
                aggregateAlive: aggregateAlive,
                effBrightness: effBrightness,
                effSpeed: effSpeed,
                effIntensity: effIntensity
            )
            publishLive(frame, sampleRate)
        }
    }
}
