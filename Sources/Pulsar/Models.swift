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
    /// PSU minimum-load floor in 0…0.5. Each output channel is raised
    /// to at least `minLoad * 255` so a flicker-prone supply stays above
    /// its stable-current threshold.
    var minLoad: Float = 0

    var id: String { name }
}

/// Audio descriptor that can drive a slider in reactive mode.
enum AudioAspect: String, Codable, CaseIterable, Equatable {
    case power, bass, treble, beat

    var label: String {
        switch self {
        case .power:  return "Power"
        case .bass:   return "Bass"
        case .treble: return "Treble"
        case .beat:   return "Beat"
        }
    }

    var symbol: String {
        switch self {
        case .power:  return "waveform"
        case .bass:   return "speaker.wave.1.fill"
        case .treble: return "speaker.wave.3.fill"
        case .beat:   return "metronome.fill"
        }
    }
}

struct LiveFrame: Equatable {
    var spectrum: [Float]
    var power: Float
    /// Normalized bass energy [0,1] — mean of bottom quartile of bands.
    var bass: Float
    /// Normalized treble energy [0,1] — mean of top quartile of bands.
    var treble: Float
    /// Decaying pulse [0,1] that spikes to 1 on each detected beat.
    var beat: Float
    var lastFrameAgo: Double
    var aggregateAlive: Bool

    static let zero = LiveFrame(spectrum: [], power: 0, bass: 0, treble: 0, beat: 0, lastFrameAgo: -1, aggregateAlive: false)

    func value(for aspect: AudioAspect) -> Float {
        switch aspect {
        case .power:  return min(1, power * 4)
        case .bass:   return bass
        case .treble: return treble
        case .beat:   return beat
        }
    }
}

struct Settings: Equatable {
    var enabled: Bool
    var effect: String
    var palette: String
    var brightness: Float
    var speed: Float
    var intensity: Float
    var brightnessReactive: Bool
    var brightnessAspect: AudioAspect
    var speedReactive: Bool
    var speedAspect: AudioAspect
    var intensityReactive: Bool
    var intensityAspect: AudioAspect
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
        brightnessReactive: false,
        brightnessAspect: .power,
        speedReactive: false,
        speedAspect: .power,
        intensityReactive: false,
        intensityAspect: .power,
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
