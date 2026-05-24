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
    let speed: Float?
    let intensity: Float?

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
        speed: 1.0,
        intensity: 1.0
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
        return cfg
    }
}
