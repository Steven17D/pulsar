import AppKit
import Combine
import Foundation
import OSLog
import SwiftUI

@MainActor
final class LiveStore: ObservableObject {
    @Published var frame: LiveFrame = .zero
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: Settings = .empty
    @Published var status: AudioStatus = .starting
}

struct RenderView {
    let enabled: Bool
    let effect: String
    let palette: Palette
    let speed: Float
    let intensity: Float
    let devices: [DeviceRuntime]
}

final class RenderState: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool = true
    private var effect: String = "spectrum"
    private var paletteID: String = "sunset"
    private var speed: Float = 1.0
    private var intensity: Float = 1.0
    private var devices: [DeviceRuntime] = []

    func snapshot() -> RenderView {
        lock.lock(); defer { lock.unlock() }
        return RenderView(
            enabled: enabled, effect: effect,
            palette: Palette.by(id: paletteID),
            speed: speed, intensity: intensity,
            devices: devices
        )
    }

    func replace(enabled: Bool, effect: String, paletteID: String, speed: Float, intensity: Float, devices: [DeviceRuntime]) {
        lock.lock(); defer { lock.unlock() }
        self.enabled = enabled
        self.effect = effect
        self.paletteID = paletteID
        self.speed = speed
        self.intensity = intensity
        self.devices = devices
    }

    func setEnabled(_ v: Bool) {
        lock.lock(); defer { lock.unlock() }
        enabled = v
    }

    func setEffect(_ e: String) {
        lock.lock(); defer { lock.unlock() }
        effect = e
    }

    func setPalette(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        paletteID = id
    }

    func setSpeed(_ s: Float) {
        lock.lock(); defer { lock.unlock() }
        speed = s
    }

    func setIntensity(_ v: Float) {
        lock.lock(); defer { lock.unlock() }
        intensity = v
    }

    func mutateDevice(index: Int, _ body: (inout DeviceRuntime) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard devices.indices.contains(index) else { return }
        body(&devices[index])
    }
}

@MainActor
final class ControlModel {
    static let shared = ControlModel()
    let log = Logger(subsystem: "io.pulsar.audio", category: "ControlModel")

    let live = LiveStore()
    let settings = SettingsStore()
    let renderState = RenderState()

    private var engine: AudioEngine?
    private var baseConfig: Config = .default
    private let saveQueue = DispatchQueue(label: "pulsar.save", qos: .utility)

    func boot() {
        let cfg = Config.load()
        baseConfig = cfg
        seedFromConfig(cfg)

        // Try discovering segments from WLED in background once at boot
        // — overrides defaults but preserves per-segment reverse/mirror
        // already in the on-disk config. Wait 2s so the engine has a
        // chance to settle before we spam the network.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refreshAllSegmentsFromWLED()
            }
        }

        guard TCCAudioCapture.available else {
            log.error("TCC SPI unavailable; aborting")
            settings.status = .tccDenied
            return
        }
        let st = TCCAudioCapture.status()
        settings.settings.tccStatus = st
        if st == 0 {
            startEngine()
            return
        }
        DispatchQueue.global().async { [weak self] in
            let ok = TCCAudioCapture.requestBlocking()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.settings.settings.tccStatus = TCCAudioCapture.status()
                if ok { self.startEngine() } else { self.settings.status = .tccDenied }
            }
        }
    }

    private func seedFromConfig(_ cfg: Config) {
        var s = Settings.empty
        s.enabled = cfg.enabled ?? true
        s.fps = cfg.fps
        s.bandCount = cfg.band_count
        // Map old effect ids to the closest new one so existing configs
        // boot into a reactive effect instead of a missing renderer.
        let rawEffect = cfg.effect ?? cfg.devices.first?.effect ?? "spectrum"
        s.effect = Self.migrateEffect(rawEffect)
        s.palette = Palette.allIDs.contains(cfg.palette ?? "") ? (cfg.palette ?? "sunset") : "sunset"
        s.speed = max(0.0, min(2.0, cfg.speed ?? 1.0))
        s.intensity = max(0.0, min(2.0, cfg.intensity ?? 1.0))
        s.devices = cfg.devices.map { d in
            let segs: [SegmentRuntime]
            if let seg = d.segments, !seg.isEmpty {
                segs = seg.map { SegmentRuntime(start: $0.start, length: $0.length, reverse: $0.reverse ?? false, mirror: $0.mirror ?? false) }
            } else {
                // Backfill: legacy single segment covering the strip,
                // carrying the legacy device-level reverse + mirror so
                // existing behaviour survives a daemon restart.
                segs = [SegmentRuntime(start: 0, length: d.pixel_count, reverse: d.reverse ?? false, mirror: d.mirror ?? false)]
            }
            return DeviceRuntime(
                name: d.name, ip: d.ip, pixelCount: d.pixel_count, rgbw: d.rgbw,
                brightness: d.brightness ?? 1.0, enabled: d.enabled ?? true,
                segments: segs
            )
        }
        settings.settings = s
        renderState.replace(
            enabled: s.enabled, effect: s.effect, paletteID: s.palette,
            speed: s.speed, intensity: s.intensity, devices: s.devices
        )
    }

    private static func migrateEffect(_ raw: String) -> String {
        if Mapper.availableEffects.contains(raw) { return raw }
        switch raw {
        case "bands_rainbow": return "spectrum"
        case "vu_meter":      return "equalizer"
        case "power_pulse":   return "solid"
        case "waterfall":     return "spectrum"
        case "sparkle":       return "strobe"
        default:              return "spectrum"
        }
    }

    private func startEngine(retry: Int = 0) {
        SystemAudioTap.destroyAggregate(uid: "io.ledfx.wled-sync")
        let engine = AudioEngine(config: baseConfig, renderState: renderState) { frame, sr in
            DispatchQueue.main.async {
                ControlModel.shared.publishLiveFrame(frame, sampleRate: sr)
            }
        }
        do {
            try engine.start()
            self.engine = engine
            settings.status = .running
        } catch {
            log.error("engine start attempt \(retry+1) failed: \(String(describing: error), privacy: .public)")
            if retry < 8 {
                settings.status = .starting
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.startEngine(retry: retry + 1)
                }
            } else {
                settings.status = .stopped
            }
        }
    }

    func publishLiveFrame(_ frame: LiveFrame, sampleRate: Double) {
        if frame != live.frame { live.frame = frame }
        if settings.settings.sampleRate != sampleRate {
            settings.settings.sampleRate = sampleRate
        }
    }

    // MARK: - Segment discovery

    /// Fetch WLED /json/cfg for each device, parse hw.led.ins[] into
    /// segments, merge with the user's stored reverse/mirror choices.
    func refreshAllSegmentsFromWLED() async {
        let devs = settings.settings.devices
        for i in devs.indices {
            await refreshSegmentsFromWLED(deviceIndex: i)
        }
    }

    func refreshSegmentsFromWLED(deviceIndex i: Int) async {
        let dev = settings.settings.devices[safe: i]
        guard let dev else { return }
        guard let url = URL(string: "http://\(dev.ip)/json/cfg") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hw = json["hw"] as? [String: Any],
                  let led = hw["led"] as? [String: Any],
                  let ins = led["ins"] as? [[String: Any]] else { return }
            var newSegs: [SegmentRuntime] = []
            for inst in ins {
                let start = inst["start"] as? Int ?? 0
                let length = inst["len"] as? Int ?? 0
                guard length > 0 else { continue }
                // Preserve existing per-segment flags if a segment with
                // matching (start, length) already exists in the runtime.
                let existing = dev.segments.first(where: { $0.start == start && $0.length == length })
                newSegs.append(SegmentRuntime(
                    start: start, length: length,
                    reverse: existing?.reverse ?? false,
                    mirror: existing?.mirror ?? false
                ))
            }
            guard !newSegs.isEmpty, newSegs != dev.segments else { return }
            settings.settings.devices[i].segments = newSegs
            renderState.mutateDevice(index: i) { $0.segments = newSegs }
            persist()
            log.info("device \(dev.name, privacy: .public) → \(newSegs.count) segments")
        } catch {
            log.error("segment refresh failed for \(dev.name, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - User actions

    func setMasterEnabled(_ v: Bool) {
        settings.settings.enabled = v
        renderState.setEnabled(v)
        persist()
    }

    func setMasterEffect(_ e: String) {
        settings.settings.effect = e
        renderState.setEffect(e)
        persist()
    }

    func setPalette(_ id: String) {
        guard Palette.allIDs.contains(id) else { return }
        settings.settings.palette = id
        renderState.setPalette(id)
        persist()
    }

    func setSpeed(_ v: Float) {
        let c = max(0, min(2, v))
        settings.settings.speed = c
        renderState.setSpeed(c)
        persist()
    }

    func setIntensity(_ v: Float) {
        let c = max(0, min(2, v))
        settings.settings.intensity = c
        renderState.setIntensity(c)
        persist()
    }

    func setDeviceEnabled(index: Int, _ v: Bool) {
        guard settings.settings.devices.indices.contains(index) else { return }
        settings.settings.devices[index].enabled = v
        renderState.mutateDevice(index: index) { $0.enabled = v }
        persist()
    }

    func setDeviceBrightness(index: Int, _ b: Float) {
        guard settings.settings.devices.indices.contains(index) else { return }
        let c = max(0, min(1, b))
        settings.settings.devices[index].brightness = c
        renderState.mutateDevice(index: index) { $0.brightness = c }
        persist()
    }

    func setSegmentReverse(deviceIndex i: Int, segmentIndex s: Int, _ v: Bool) {
        guard settings.settings.devices.indices.contains(i),
              settings.settings.devices[i].segments.indices.contains(s) else { return }
        settings.settings.devices[i].segments[s].reverse = v
        renderState.mutateDevice(index: i) { $0.segments[s].reverse = v }
        persist()
    }

    func setSegmentMirror(deviceIndex i: Int, segmentIndex s: Int, _ v: Bool) {
        guard settings.settings.devices.indices.contains(i),
              settings.settings.devices[i].segments.indices.contains(s) else { return }
        settings.settings.devices[i].segments[s].mirror = v
        renderState.mutateDevice(index: i) { $0.segments[s].mirror = v }
        persist()
    }

    func reloadFromDisk() {
        let cfg = Config.load()
        baseConfig = cfg
        seedFromConfig(cfg)
    }

    func quit() {
        engine?.stop()
        NSApp.terminate(nil)
    }

    private func persist() {
        let snap = settings.settings
        let cfg = baseConfig
        saveQueue.async {
            let newDevs = snap.devices.map { d in
                DeviceConfig(
                    name: d.name, ip: d.ip, pixel_count: d.pixelCount, rgbw: d.rgbw,
                    brightness: d.brightness, enabled: d.enabled,
                    segments: d.segments.map { s in
                        SegmentConfig(start: s.start, length: s.length, reverse: s.reverse, mirror: s.mirror)
                    },
                    mirror: nil, reverse: nil, effect: nil
                )
            }
            let out = Config(
                fps: cfg.fps, fft_size: cfg.fft_size, band_count: cfg.band_count,
                smoothing: cfg.smoothing, min_freq_hz: cfg.min_freq_hz,
                max_freq_hz: cfg.max_freq_hz, devices: newDevs,
                enabled: snap.enabled, effect: snap.effect,
                palette: snap.palette, speed: snap.speed, intensity: snap.intensity
            )
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(out) {
                try? data.write(to: URL(fileURLWithPath: Config.defaultPath), options: .atomic)
            }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
