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
        devices: [
            DeviceConfig(name: "Office", ip: "192.168.0.192", pixel_count: 237, rgbw: false, brightness: nil, enabled: nil, segments: nil, mirror: nil, reverse: nil, effect: nil),
            DeviceConfig(name: "TV",     ip: "192.168.0.186", pixel_count: 240, rgbw: false, brightness: nil, enabled: nil, segments: nil, mirror: nil, reverse: nil, effect: nil),
        ],
        enabled: nil,
        effect: "spectrum",
        palette: "sunset",
        speed: 1.0,
        intensity: 1.0
    )

    static func load(_ path: String? = nil) -> Config {
        let p = path ?? defaultPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: p)) else { return .default }
        guard let cfg = try? JSONDecoder().decode(Config.self, from: data) else {
            FileHandle.standardError.write(Data("Pulsar: config at \(p) failed to parse; using defaults\n".utf8))
            return .default
        }
        return cfg
    }
}
