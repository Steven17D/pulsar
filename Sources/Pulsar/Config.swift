import Foundation

struct SegmentConfig: Codable {
    let start: Int
    let length: Int
    let reverse: Bool?
    let mirror: Bool?
}

struct DeviceConfig: Codable {
    let name: String
    let ip: String
    let pixel_count: Int
    let rgbw: Bool
    let brightness: Float?
    let enabled: Bool?
    let segments: [SegmentConfig]?
    /// Hardware compensation: floor each LED channel output to at least
    /// this fraction of full scale. Use to keep a flicker-prone PSU
    /// above its minimum stable load. 0 disables.
    let min_load: Float?
    // Legacy fields kept optional so older configs parse. mirror+reverse
    // at device level are no-ops once `segments` is populated. `effect`
    // moved to the root Config.
    let mirror: Bool?
    let reverse: Bool?
    let effect: String?
}

struct Config: Codable {
    let fps: Int
    let fft_size: Int
    let band_count: Int
    let smoothing: Float
    let min_freq_hz: Double
    let max_freq_hz: Double
    let devices: [DeviceConfig]
    let enabled: Bool?
    let effect: String?
    let palette: String?
    let brightness: Float?
    let speed: Float?
    let intensity: Float?
    let brightness_reactive: Bool?
    let brightness_aspect: AudioAspect?
    let speed_reactive: Bool?
    let speed_aspect: AudioAspect?
    let intensity_reactive: Bool?
    let intensity_aspect: AudioAspect?

    static let defaultPath: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return "\(home)/.config/pulsar/config.json"
    }()

    static let `default` = Config(
        fps: 60,
        fft_size: 1024,
        band_count: 32,
        smoothing: 0.6,
        min_freq_hz: 40,
        max_freq_hz: 16000,
        devices: [],
        enabled: nil,
        effect: "spectrum",
        palette: "sunset",
        brightness: 1.0,
        speed: 1.0,
        intensity: 1.0,
        brightness_reactive: nil,
        brightness_aspect: nil,
        speed_reactive: nil,
        speed_aspect: nil,
        intensity_reactive: nil,
        intensity_aspect: nil
    )

    /// Loads config from `path` (or the default location). On first run,
    /// writes a fresh `.default` to disk so the file is always discoverable.
    static func load(_ path: String? = nil) -> Config {
        let p = path ?? defaultPath
        let url = URL(fileURLWithPath: p)
        if !FileManager.default.fileExists(atPath: p) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(Config.default) {
                try? data.write(to: url, options: .atomic)
            }
            return .default
        }
        guard let data = try? Data(contentsOf: url) else { return .default }
        guard let cfg = try? JSONDecoder().decode(Config.self, from: data) else {
            FileHandle.standardError.write(Data("Pulsar: config at \(p) failed to parse; using defaults\n".utf8))
            return .default
        }
        return cfg.sanitized()
    }

    func sanitized() -> Config {
        let fallback = Config.default
        let validFFT = fft_size > 0 && (fft_size & (fft_size - 1)) == 0
        let safeFFT = validFFT ? fft_size : fallback.fft_size
        let safeMinFreq = min_freq_hz.isFinite && min_freq_hz > 0 ? min_freq_hz : fallback.min_freq_hz
        let safeMaxFreq = max_freq_hz.isFinite && max_freq_hz > safeMinFreq ? max_freq_hz : fallback.max_freq_hz

        return Config(
            fps: fps.clamped(to: 1...120),
            fft_size: safeFFT.clamped(to: 256...8192),
            band_count: band_count.clamped(to: 1...128),
            smoothing: smoothing.clamped(to: 0...0.99),
            min_freq_hz: safeMinFreq,
            max_freq_hz: safeMaxFreq,
            devices: devices.compactMap { $0.sanitized() },
            enabled: enabled,
            effect: effect,
            palette: palette,
            brightness: brightness?.clamped(to: 0...1),
            speed: speed?.clamped(to: 0...2),
            intensity: intensity?.clamped(to: 0...2),
            brightness_reactive: brightness_reactive,
            brightness_aspect: brightness_aspect,
            speed_reactive: speed_reactive,
            speed_aspect: speed_aspect,
            intensity_reactive: intensity_reactive,
            intensity_aspect: intensity_aspect
        )
    }
}

private extension DeviceConfig {
    func sanitized() -> DeviceConfig? {
        let safeName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeName.isEmpty, !safeIP.isEmpty, pixel_count > 0 else { return nil }
        let safePixelCount = pixel_count.clamped(to: 1...100_000)
        let safeSegments = segments?
            .compactMap { $0.sanitized(pixelCount: safePixelCount) }
            .nilIfEmpty

        return DeviceConfig(
            name: safeName,
            ip: safeIP,
            pixel_count: safePixelCount,
            rgbw: rgbw,
            brightness: brightness?.clamped(to: 0...1),
            enabled: enabled,
            segments: safeSegments,
            min_load: min_load?.clamped(to: 0...0.5),
            mirror: mirror,
            reverse: reverse,
            effect: effect
        )
    }
}

private extension SegmentConfig {
    func sanitized(pixelCount: Int) -> SegmentConfig? {
        let safeStart = start.clamped(to: 0...max(pixelCount - 1, 0))
        let available = max(pixelCount - safeStart, 0)
        let safeLength = length.clamped(to: 1...max(available, 1))
        guard available > 0 else { return nil }
        return SegmentConfig(
            start: safeStart,
            length: safeLength,
            reverse: reverse,
            mirror: mirror
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Array {
    var nilIfEmpty: [Element]? {
        isEmpty ? nil : self
    }
}
