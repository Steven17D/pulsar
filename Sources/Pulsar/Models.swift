import Foundation

struct SegmentRuntime: Equatable, Identifiable {
    var start: Int
    var length: Int
    var reverse: Bool
    var mirror: Bool

    var id: String { "\(start)-\(length)" }
}

struct DeviceRuntime: Equatable, Identifiable {
    var name: String
    var ip: String
    var pixelCount: Int
    var rgbw: Bool
    var brightness: Float
    var enabled: Bool
    var segments: [SegmentRuntime]

    var id: String { name }
}

struct LiveFrame: Equatable {
    var spectrum: [Float]
    var power: Float
    var lastFrameAgo: Double
    var aggregateAlive: Bool

    static let zero = LiveFrame(spectrum: [], power: 0, lastFrameAgo: -1, aggregateAlive: false)
}

struct Settings: Equatable {
    var enabled: Bool
    var effect: String
    var palette: String
    var brightness: Float
    var speed: Float
    var intensity: Float
    var devices: [DeviceRuntime]
    var availableEffects: [String]
    var availablePalettes: [String]
    var fps: Int
    var sampleRate: Double
    var bandCount: Int
    var tccStatus: Int

    static let empty = Settings(
        enabled: true,
        effect: "spectrum",
        palette: "sunset",
        brightness: 1.0,
        speed: 1.0,
        intensity: 1.0,
        devices: [],
        availableEffects: Mapper.availableEffects,
        availablePalettes: Palette.allIDs,
        fps: 60, sampleRate: 0, bandCount: 32, tccStatus: -1
    )
}

enum AudioStatus: Equatable {
    case starting
    case running
    case stopped
    case tccDenied
    case aggregateLost
}
