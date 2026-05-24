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
    let brightness: Float
    let speed: Float
    let intensity: Float
    let brightnessReactive: Bool
    let brightnessAspect: AudioAspect
    let speedReactive: Bool
    let speedAspect: AudioAspect
    let intensityReactive: Bool
    let intensityAspect: AudioAspect
    let devices: [DeviceRuntime]
}

final class RenderState: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool = true
    private var effect: String = "spectrum"
    private var paletteID: String = "sunset"
    private var brightness: Float = 1.0
    private var speed: Float = 1.0
    private var intensity: Float = 1.0
    private var brightnessReactive: Bool = false
    private var brightnessAspect: AudioAspect = .power
    private var speedReactive: Bool = false
    private var speedAspect: AudioAspect = .power
    private var intensityReactive: Bool = false
    private var intensityAspect: AudioAspect = .power
    private var devices: [DeviceRuntime] = []

    func snapshot() -> RenderView {
        lock.lock(); defer { lock.unlock() }
        return RenderView(
            enabled: enabled, effect: effect,
            palette: Palette.by(id: paletteID),
            brightness: brightness,
            speed: speed, intensity: intensity,
            brightnessReactive: brightnessReactive,
            brightnessAspect: brightnessAspect,
            speedReactive: speedReactive,
            speedAspect: speedAspect,
            intensityReactive: intensityReactive,
            intensityAspect: intensityAspect,
            devices: devices
        )
    }

    func replace(enabled: Bool, effect: String, paletteID: String, brightness: Float, speed: Float, intensity: Float,
                 brightnessReactive: Bool, brightnessAspect: AudioAspect,
                 speedReactive: Bool, speedAspect: AudioAspect,
                 intensityReactive: Bool, intensityAspect: AudioAspect,
                 devices: [DeviceRuntime]) {
        lock.lock(); defer { lock.unlock() }
        self.enabled = enabled
        self.effect = effect
        self.paletteID = paletteID
        self.brightness = brightness
        self.speed = speed
        self.intensity = intensity
        self.brightnessReactive = brightnessReactive
        self.brightnessAspect = brightnessAspect
        self.speedReactive = speedReactive
        self.speedAspect = speedAspect
        self.intensityReactive = intensityReactive
        self.intensityAspect = intensityAspect
        self.devices = devices
    }

    func setBrightnessReactive(_ v: Bool) {
        lock.lock(); defer { lock.unlock() }
        brightnessReactive = v
    }
    func setBrightnessAspect(_ a: AudioAspect) {
        lock.lock(); defer { lock.unlock() }
        brightnessAspect = a
    }
    func setSpeedReactive(_ v: Bool) {
        lock.lock(); defer { lock.unlock() }
        speedReactive = v
    }
    func setSpeedAspect(_ a: AudioAspect) {
        lock.lock(); defer { lock.unlock() }
        speedAspect = a
    }
    func setIntensityReactive(_ v: Bool) {
        lock.lock(); defer { lock.unlock() }
        intensityReactive = v
    }
    func setIntensityAspect(_ a: AudioAspect) {
        lock.lock(); defer { lock.unlock() }
        intensityAspect = a
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

    func setBrightness(_ v: Float) {
        lock.lock(); defer { lock.unlock() }
        brightness = v
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
final class ControlModel: ObservableObject {
    static let shared = ControlModel()
    let log = Logger(subsystem: "io.pulsar.audio", category: "ControlModel")

    let live = LiveStore()
    let settings = SettingsStore()
    let renderState = RenderState()
    let discovery = WLEDDiscovery()

    @Published private(set) var startAtLogin: Bool = false
    @Published var startupNotice: String?

    private var engine: AudioEngine?
    private var baseConfig: Config = .default
    private let saveQueue = DispatchQueue(label: "pulsar.save", qos: .utility)

    private var launchAgentPlistPath: String {
        "\(NSHomeDirectory())/Library/LaunchAgents/io.pulsar.audio.plist"
    }

    func boot() {
        let cfg = Config.load()
        baseConfig = cfg
        seedFromConfig(cfg)
        refreshStartAtLoginState()

        discovery.start()

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
        s.brightness = max(0.0, min(1.0, cfg.brightness ?? 1.0))
        s.speed = max(0.0, min(2.0, cfg.speed ?? 1.0))
        s.intensity = max(0.0, min(2.0, cfg.intensity ?? 1.0))
        s.brightnessReactive = cfg.brightness_reactive ?? false
        s.brightnessAspect = cfg.brightness_aspect ?? .power
        s.speedReactive = cfg.speed_reactive ?? false
        s.speedAspect = cfg.speed_aspect ?? .power
        s.intensityReactive = cfg.intensity_reactive ?? false
        s.intensityAspect = cfg.intensity_aspect ?? .power
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
                segments: segs,
                minLoad: d.min_load ?? 0
            )
        }
        settings.settings = s
        renderState.replace(
            enabled: s.enabled, effect: s.effect, paletteID: s.palette,
            brightness: s.brightness,
            speed: s.speed, intensity: s.intensity,
            brightnessReactive: s.brightnessReactive, brightnessAspect: s.brightnessAspect,
            speedReactive: s.speedReactive, speedAspect: s.speedAspect,
            intensityReactive: s.intensityReactive, intensityAspect: s.intensityAspect,
            devices: s.devices
        )
    }

    private static func migrateEffect(_ raw: String) -> String {
        if Mapper.availableEffects.contains(raw) { return raw }
        switch raw {
        case "bands_rainbow": return "spectrum"
        case "vu_meter":      return "spectrum"
        case "power_pulse":   return "solid"
        case "waterfall":     return "spectrum"
        case "sparkle":       return "glitter"
        default:              return "spectrum"
        }
    }

    private func startEngine(retry: Int = 0) {
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
            var snap = settings.settings
            snap.sampleRate = sampleRate
            settings.settings = snap
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
            let info = await fetchWLEDInfo(ip: dev.ip)
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
            let newPixelCount = info.pixelCount ?? dev.pixelCount
            let newRGBW = info.rgbw ?? dev.rgbw
            let needsEngineRebuild = newPixelCount != dev.pixelCount || newRGBW != dev.rgbw
            let changed = newSegs != dev.segments || needsEngineRebuild
            guard !newSegs.isEmpty, changed else { return }
            var snap = settings.settings
            snap.devices[i].pixelCount = newPixelCount
            snap.devices[i].rgbw = newRGBW
            snap.devices[i].segments = newSegs
            settings.settings = snap
            renderState.mutateDevice(index: i) {
                $0.pixelCount = newPixelCount
                $0.rgbw = newRGBW
                $0.segments = newSegs
            }
            persist()
            if needsEngineRebuild { rebuildEngine() }
            log.info("device \(dev.name, privacy: .public) → \(newSegs.count) segments")
        } catch {
            log.error("segment refresh failed for \(dev.name, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func fetchWLEDInfo(ip: String) async -> (pixelCount: Int?, rgbw: Bool?) {
        guard let url = URL(string: "http://\(ip)/json/info") else { return (nil, nil) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let leds = json["leds"] as? [String: Any] else {
            return (nil, nil)
        }
        return (leds["count"] as? Int, leds["rgbw"] as? Bool)
    }

    // MARK: - User actions

    func setMasterEnabled(_ v: Bool) {
        var snap = settings.settings
        snap.enabled = v
        settings.settings = snap
        renderState.setEnabled(v)
        persist()
    }

    func setMasterEffect(_ e: String) {
        var snap = settings.settings
        snap.effect = e
        settings.settings = snap
        renderState.setEffect(e)
        persist()
    }

    func setPalette(_ id: String) {
        guard Palette.allIDs.contains(id) else { return }
        var snap = settings.settings
        snap.palette = id
        settings.settings = snap
        renderState.setPalette(id)
        persist()
    }

    func setBrightness(_ v: Float) {
        let c = max(0, min(1, v))
        var snap = settings.settings
        snap.brightness = c
        settings.settings = snap
        renderState.setBrightness(c)
        persist()
    }

    func setSpeed(_ v: Float) {
        let c = max(0, min(2, v))
        var snap = settings.settings
        snap.speed = c
        settings.settings = snap
        renderState.setSpeed(c)
        persist()
    }

    func setIntensity(_ v: Float) {
        let c = max(0, min(2, v))
        var snap = settings.settings
        snap.intensity = c
        settings.settings = snap
        renderState.setIntensity(c)
        persist()
    }

    func setBrightnessReactive(_ v: Bool) {
        var snap = settings.settings
        snap.brightnessReactive = v
        settings.settings = snap
        renderState.setBrightnessReactive(v)
        persist()
    }
    func setBrightnessAspect(_ a: AudioAspect) {
        var snap = settings.settings
        snap.brightnessAspect = a
        settings.settings = snap
        renderState.setBrightnessAspect(a)
        persist()
    }
    func setSpeedReactive(_ v: Bool) {
        var snap = settings.settings
        snap.speedReactive = v
        settings.settings = snap
        renderState.setSpeedReactive(v)
        persist()
    }
    func setSpeedAspect(_ a: AudioAspect) {
        var snap = settings.settings
        snap.speedAspect = a
        settings.settings = snap
        renderState.setSpeedAspect(a)
        persist()
    }
    func setIntensityReactive(_ v: Bool) {
        var snap = settings.settings
        snap.intensityReactive = v
        settings.settings = snap
        renderState.setIntensityReactive(v)
        persist()
    }
    func setIntensityAspect(_ a: AudioAspect) {
        var snap = settings.settings
        snap.intensityAspect = a
        settings.settings = snap
        renderState.setIntensityAspect(a)
        persist()
    }

    func setDeviceEnabled(index: Int, _ v: Bool) {
        guard settings.settings.devices.indices.contains(index) else { return }
        var snap = settings.settings
        snap.devices[index].enabled = v
        settings.settings = snap
        renderState.mutateDevice(index: index) { $0.enabled = v }
        persist()
    }

    func setDeviceBrightness(index: Int, _ b: Float) {
        guard settings.settings.devices.indices.contains(index) else { return }
        let c = max(0, min(1, b))
        var snap = settings.settings
        snap.devices[index].brightness = c
        settings.settings = snap
        renderState.mutateDevice(index: index) { $0.brightness = c }
        persist()
    }

    func setDeviceMinLoad(index: Int, _ v: Float) {
        guard settings.settings.devices.indices.contains(index) else { return }
        let c = max(0, min(0.5, v))
        var snap = settings.settings
        snap.devices[index].minLoad = c
        settings.settings = snap
        renderState.mutateDevice(index: index) { $0.minLoad = c }
        persist()
    }

    func setDeviceRGBW(index: Int, _ rgbw: Bool) {
        guard settings.settings.devices.indices.contains(index),
              settings.settings.devices[index].rgbw != rgbw else { return }
        var snap = settings.settings
        snap.devices[index].rgbw = rgbw
        settings.settings = snap
        renderState.mutateDevice(index: index) { $0.rgbw = rgbw }
        persist()
        rebuildEngine()
    }

    func setSegmentReverse(deviceIndex i: Int, segmentIndex s: Int, _ v: Bool) {
        guard settings.settings.devices.indices.contains(i),
              settings.settings.devices[i].segments.indices.contains(s) else { return }
        var snap = settings.settings
        snap.devices[i].segments[s].reverse = v
        settings.settings = snap
        renderState.mutateDevice(index: i) { $0.segments[s].reverse = v }
        persist()
    }

    func setSegmentMirror(deviceIndex i: Int, segmentIndex s: Int, _ v: Bool) {
        guard settings.settings.devices.indices.contains(i),
              settings.settings.devices[i].segments.indices.contains(s) else { return }
        var snap = settings.settings
        snap.devices[i].segments[s].mirror = v
        settings.settings = snap
        renderState.mutateDevice(index: i) { $0.segments[s].mirror = v }
        persist()
    }

    // MARK: - Device CRUD

    /// Inserts a new device, persists, then refreshes its segments.
    func addDevice(name: String, ip: String, pixelCount: Int, rgbw: Bool) {
        guard !ip.isEmpty, !name.isEmpty, pixelCount > 0 else { return }
        if settings.settings.devices.contains(where: { $0.ip == ip }) { return }
        let dev = DeviceRuntime(
            name: name, ip: ip, pixelCount: pixelCount, rgbw: rgbw,
            brightness: 1.0, enabled: true,
            segments: [SegmentRuntime(start: 0, length: pixelCount, reverse: false, mirror: false)],
            minLoad: 0
        )
        var snap = settings.settings
        snap.devices.append(dev)
        settings.settings = snap
        var devs = renderState.snapshot().devices
        devs.append(dev)
        renderState.replace(
            enabled: settings.settings.enabled,
            effect: settings.settings.effect,
            paletteID: settings.settings.palette,
            brightness: settings.settings.brightness,
            speed: settings.settings.speed,
            intensity: settings.settings.intensity,
            brightnessReactive: settings.settings.brightnessReactive,
            brightnessAspect: settings.settings.brightnessAspect,
            speedReactive: settings.settings.speedReactive,
            speedAspect: settings.settings.speedAspect,
            intensityReactive: settings.settings.intensityReactive,
            intensityAspect: settings.settings.intensityAspect,
            devices: devs
        )
        persist()
        let newIndex = settings.settings.devices.count - 1
        Task { @MainActor [weak self] in
            await self?.refreshSegmentsFromWLED(deviceIndex: newIndex)
        }
        rebuildEngine()
    }

    func removeDevice(index: Int) {
        guard settings.settings.devices.indices.contains(index) else { return }
        var snap = settings.settings
        snap.devices.remove(at: index)
        settings.settings = snap
        var devs = renderState.snapshot().devices
        if devs.indices.contains(index) { devs.remove(at: index) }
        renderState.replace(
            enabled: settings.settings.enabled,
            effect: settings.settings.effect,
            paletteID: settings.settings.palette,
            brightness: settings.settings.brightness,
            speed: settings.settings.speed,
            intensity: settings.settings.intensity,
            brightnessReactive: settings.settings.brightnessReactive,
            brightnessAspect: settings.settings.brightnessAspect,
            speedReactive: settings.settings.speedReactive,
            speedAspect: settings.settings.speedAspect,
            intensityReactive: settings.settings.intensityReactive,
            intensityAspect: settings.settings.intensityAspect,
            devices: devs
        )
        persist()
        rebuildEngine()
    }

    func renameDevice(index: Int, to name: String) {
        guard settings.settings.devices.indices.contains(index), !name.isEmpty else { return }
        var snap = settings.settings
        snap.devices[index].name = name
        settings.settings = snap
        renderState.mutateDevice(index: index) { $0.name = name }
        persist()
    }

    /// Restarts the audio engine so DDP senders + mappers reflect the
    /// current device list. Cheap; the tap teardown + recreate is bounded.
    private func rebuildEngine() {
        engine?.stop()
        engine = nil
        guard settings.status == .running || settings.status == .starting else { return }
        startEngine()
    }

    func reloadFromDisk() {
        let cfg = Config.load()
        baseConfig = cfg
        seedFromConfig(cfg)
    }

    // MARK: - Startup

    private func refreshStartAtLoginState() {
        startAtLogin = FileManager.default.fileExists(atPath: launchAgentPlistPath)
    }

    func setStartAtLogin(_ enabled: Bool) {
        startupNotice = nil
        if enabled {
            installLaunchAgent()
        } else {
            uninstallLaunchAgent()
        }
        refreshStartAtLoginState()
    }

    private func installLaunchAgent() {
        guard let plist = makeLaunchAgentPlist() else {
            startupNotice = "Unable to find the running Pulsar binary."
            return
        }
        let plistURL = URL(fileURLWithPath: launchAgentPlistPath)
        let agentDir = plistURL.deletingLastPathComponent()
        let cacheDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cache", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
            runLaunchctl(["bootstrap", "gui/\(getuid())", launchAgentPlistPath])
        } catch {
            startupNotice = "Could not install the startup item."
            log.error("LaunchAgent install failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func uninstallLaunchAgent() {
        if getppid() == 1 {
            startupNotice = "Pulsar will not start at login next time. Quit and relaunch to unload the current startup job."
        } else {
            runLaunchctl(["bootout", "gui/\(getuid())/io.pulsar.audio"])
        }
        do {
            try FileManager.default.removeItem(atPath: launchAgentPlistPath)
        } catch {
            if !FileManager.default.fileExists(atPath: launchAgentPlistPath) { return }
            startupNotice = "Could not remove the startup item."
            log.error("LaunchAgent removal failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func makeLaunchAgentPlist() -> String? {
        guard let executablePath = Bundle.main.executablePath else { return nil }
        let home = NSHomeDirectory()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>io.pulsar.audio</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(Self.xmlEscaped(executablePath))</string>
          </array>
          <key>RunAtLoad</key><true/>
          <key>KeepAlive</key>
          <dict>
            <key>SuccessfulExit</key><false/>
            <key>Crashed</key><true/>
          </dict>
          <key>LimitLoadToSessionType</key><string>Aqua</string>
          <key>ProcessType</key><string>Interactive</string>
          <key>ThrottleInterval</key><integer>30</integer>
          <key>StandardOutPath</key><string>\(Self.xmlEscaped(home))/.cache/pulsar.log</string>
          <key>StandardErrorPath</key><string>\(Self.xmlEscaped(home))/.cache/pulsar.log</string>
        </dict>
        </plist>
        """
    }

    private static func xmlEscaped(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func runLaunchctl(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            startupNotice = "Could not update the startup item."
            log.error("launchctl failed: \(String(describing: error), privacy: .public)")
        }
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
                    min_load: d.minLoad > 0 ? d.minLoad : nil,
                    mirror: nil, reverse: nil, effect: nil
                )
            }
            let out = Config(
                fps: cfg.fps, fft_size: cfg.fft_size, band_count: cfg.band_count,
                smoothing: cfg.smoothing, min_freq_hz: cfg.min_freq_hz,
                max_freq_hz: cfg.max_freq_hz, devices: newDevs,
                enabled: snap.enabled, effect: snap.effect,
                palette: snap.palette, brightness: snap.brightness,
                speed: snap.speed, intensity: snap.intensity,
                brightness_reactive: snap.brightnessReactive,
                brightness_aspect: snap.brightnessAspect,
                speed_reactive: snap.speedReactive,
                speed_aspect: snap.speedAspect,
                intensity_reactive: snap.intensityReactive,
                intensity_aspect: snap.intensityAspect
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
