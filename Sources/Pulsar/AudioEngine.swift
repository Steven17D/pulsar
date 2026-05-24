import AudioToolbox
import Darwin
import Foundation
import OSLog

final class AudioEngine: @unchecked Sendable {
    private let log = Logger(subsystem: "io.pulsar.audio", category: "AudioEngine")
    private let renderState: RenderState
    private let publishLive: @Sendable (LiveFrame, Double) -> Void
    private let cfg: Config
    private let tap = SystemAudioTap()

    private var ring: [Float]
    private var writePos: Int = 0
    private var samplesAvailable: Int = 0
    private var ioCallbacks: Int = 0
    private var ioFrames: Int = 0
    private let ringLock = NSLock()
    private let ringCapacity: Int

    private var senders: [DDPSender] = []
    private var mappers: [Mapper] = []

    private var thread: Thread?
    private var shouldRun: Bool = true

    init(config: Config, renderState: RenderState, publishLive: @escaping @Sendable (LiveFrame, Double) -> Void) {
        self.cfg = config
        self.renderState = renderState
        self.publishLive = publishLive
        self.ringCapacity = max(config.fft_size * 4, 16384)
        self.ring = [Float](repeating: 0, count: ringCapacity)
        let view = renderState.snapshot()
        for dev in view.devices {
            senders.append(DDPSender(host: dev.ip, rgbw: dev.rgbw, queueLabel: "ddp.\(dev.name)"))
            mappers.append(Mapper(totalPixels: dev.pixelCount, rgbw: dev.rgbw, effect: view.effect, segments: dev.segments))
        }
    }

    func start() throws {
        try tap.start { [weak self] ptr, frameCount, channels in
            guard let self else { return }
            self.ringLock.lock()
            defer { self.ringLock.unlock() }
            self.ioCallbacks += 1
            self.ioFrames += frameCount
            for i in 0..<frameCount {
                var s: Float = 0
                for c in 0..<channels { s += ptr[i * channels + c] }
                s /= Float(max(channels, 1))
                self.ring[self.writePos] = s
                self.writePos = (self.writePos + 1) % self.ringCapacity
            }
            self.samplesAvailable = min(self.samplesAvailable + frameCount, self.ringCapacity)
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
        let n = cfg.fft_size

        while shouldRun {
            let now = monotonicSeconds()
            let sleep = frameInterval - (now - lastTick)
            if sleep > 0 { Thread.sleep(forTimeInterval: sleep) }
            lastTick = monotonicSeconds()

            ringLock.lock()
            let haveWindow = samplesAvailable >= n
            let start = ((writePos - n) % ringCapacity + ringCapacity) % ringCapacity
            if haveWindow {
                for i in 0..<n {
                    window[i] = ring[(start + i) % ringCapacity]
                }
            }
            ringLock.unlock()

            var powerOut: Float = 0
            if haveWindow {
                window.withUnsafeBufferPointer { wPtr in
                    analyzer.process(wPtr.baseAddress!)
                }
                let power = window.withUnsafeBufferPointer { SpectrumAnalyzer.rms($0.baseAddress!, $0.count) }
                powerOut = power

                let view = renderState.snapshot()
                let masterOn = view.enabled

                if masterOn != masterWasEnabled, !masterOn {
                    for i in 0..<mappers.count {
                        mappers[i].writeBlack(into: &pixelBytes)
                        senders[i].send(pixels: pixelBytes)
                    }
                }
                masterWasEnabled = masterOn

                for i in 0..<mappers.count {
                    let dev = i < view.devices.count ? view.devices[i] : nil
                    let devOn = dev?.enabled ?? true
                    mappers[i].effect = view.effect
                    mappers[i].palette = view.palette
                    mappers[i].speed = view.speed
                    mappers[i].intensity = view.intensity
                    mappers[i].brightness = view.brightness * (dev?.brightness ?? 1.0)
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
                    mappers[i].render(bands: analyzer.bands, power: power, dt: dt)
                    mappers[i].serialize(into: &pixelBytes)
                    senders[i].send(pixels: pixelBytes)
                }
            }

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
                lastFrameAgo: 0,
                aggregateAlive: aggregateAlive
            )
            publishLive(frame, sampleRate)
        }
    }
}
