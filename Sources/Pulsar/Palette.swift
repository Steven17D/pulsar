import Foundation

/// Built-in palettes. Each is a list of (position, RGB) stops in [0,1];
/// `sample(at:)` linearly interpolates. Effects read RGB and feed
/// through `Pixel.fromLinear` which handles the RGBW W-channel split.
struct Palette: Equatable {
    let id: String
    let name: String
    let stops: [Stop]

    struct Stop: Equatable {
        let pos: Float
        let r: Float
        let g: Float
        let b: Float
    }

    static let sunset = Palette(id: "sunset", name: "Sunset", stops: [
        Stop(pos: 0.0,  r: 0.05, g: 0.0,  b: 0.2),
        Stop(pos: 0.30, r: 0.6,  g: 0.05, b: 0.4),
        Stop(pos: 0.60, r: 1.0,  g: 0.3,  b: 0.1),
        Stop(pos: 0.85, r: 1.0,  g: 0.7,  b: 0.0),
        Stop(pos: 1.0,  r: 1.0,  g: 0.95, b: 0.6),
    ])
    static let ocean = Palette(id: "ocean", name: "Ocean", stops: [
        Stop(pos: 0.0,  r: 0.0, g: 0.05, b: 0.25),
        Stop(pos: 0.30, r: 0.0, g: 0.20, b: 0.65),
        Stop(pos: 0.60, r: 0.0, g: 0.55, b: 0.80),
        Stop(pos: 0.85, r: 0.2, g: 0.90, b: 0.95),
        Stop(pos: 1.0,  r: 0.9, g: 1.00, b: 1.00),
    ])
    static let forest = Palette(id: "forest", name: "Forest", stops: [
        Stop(pos: 0.0,  r: 0.0,  g: 0.10, b: 0.05),
        Stop(pos: 0.30, r: 0.05, g: 0.45, b: 0.15),
        Stop(pos: 0.60, r: 0.30, g: 0.75, b: 0.20),
        Stop(pos: 0.85, r: 0.80, g: 0.85, b: 0.20),
        Stop(pos: 1.0,  r: 1.00, g: 0.90, b: 0.40),
    ])
    static let cyberpunk = Palette(id: "cyberpunk", name: "Cyberpunk", stops: [
        Stop(pos: 0.0,  r: 0.10, g: 0.0,  b: 0.30),
        Stop(pos: 0.25, r: 0.90, g: 0.05, b: 0.70),
        Stop(pos: 0.50, r: 0.40, g: 0.0,  b: 1.00),
        Stop(pos: 0.75, r: 0.0,  g: 0.80, b: 1.00),
        Stop(pos: 1.0,  r: 0.60, g: 1.00, b: 1.00),
    ])
    static let fire = Palette(id: "fire", name: "Fire", stops: [
        Stop(pos: 0.0,  r: 0.0, g: 0.0,  b: 0.0),
        Stop(pos: 0.20, r: 0.5, g: 0.0,  b: 0.0),
        Stop(pos: 0.50, r: 1.0, g: 0.20, b: 0.0),
        Stop(pos: 0.80, r: 1.0, g: 0.70, b: 0.0),
        Stop(pos: 1.0,  r: 1.0, g: 1.00, b: 0.85),
    ])

    static let all: [Palette] = [.sunset, .ocean, .forest, .cyberpunk, .fire]
    static let allIDs: [String] = all.map(\.id)

    static func by(id: String) -> Palette {
        all.first { $0.id == id } ?? .sunset
    }

    /// Sample palette at position t ∈ [0,1] with wraparound clamping.
    /// Returns linear RGB triplet 0..1.
    func sample(at t: Float) -> (r: Float, g: Float, b: Float) {
        let tt = max(0, min(1, t))
        var lo = stops.first!
        var hi = stops.last!
        for s in stops {
            if s.pos >= tt { hi = s; break }
            lo = s
        }
        let span = hi.pos - lo.pos
        let frac = span > 0 ? (tt - lo.pos) / span : 0
        return (
            lo.r + (hi.r - lo.r) * frac,
            lo.g + (hi.g - lo.g) * frac,
            lo.b + (hi.b - lo.b) * frac
        )
    }
}

extension Pixel {
    /// Build a pixel from linear RGB floats (0..1) scaled by value v
    /// (0..1). For RGBW strips the min-of-RGB is split into the W
    /// channel so coloured-white sections render through the W LED.
    static func fromRGB(_ r: Float, _ g: Float, _ b: Float, v: Float, rgbw: Bool) -> Pixel {
        let vv = max(0, min(1, v))
        let rr = max(0, min(1, r)) * vv
        let gg = max(0, min(1, g)) * vv
        let bb = max(0, min(1, b)) * vv
        if rgbw {
            let m = min(min(rr, gg), bb)
            return Pixel(
                r: UInt8(clamping: Int((rr - m) * 255)),
                g: UInt8(clamping: Int((gg - m) * 255)),
                b: UInt8(clamping: Int((bb - m) * 255)),
                w: UInt8(clamping: Int(m * 255))
            )
        } else {
            return Pixel(
                r: UInt8(clamping: Int(rr * 255)),
                g: UInt8(clamping: Int(gg * 255)),
                b: UInt8(clamping: Int(bb * 255)),
                w: 0
            )
        }
    }
}
