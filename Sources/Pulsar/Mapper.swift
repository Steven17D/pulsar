import Foundation

struct Pixel { var r: UInt8; var g: UInt8; var b: UInt8; var w: UInt8 }

extension Pixel {
    static let off = Pixel(r: 0, g: 0, b: 0, w: 0)
}

/// Simple onset detector: keeps a smoothed baseline of power and
/// triggers when current power exceeds baseline by a multiplier. A
/// refractory period prevents double-triggers within a single drum hit.
struct BeatDetector {
    var baseline: Float = 0
    var holdoff: Float = 0
    var mult: Float = 1.6
    var refractory: Float = 0.11

    /// Returns true on a fresh onset. `sensitivity` ∈ (0,2] scales how
    /// much the current sample must exceed the baseline — higher means
    /// easier to trigger.
    mutating func update(power: Float, dt: Float, sensitivity: Float = 1.0) -> Bool {
        baseline = baseline * 0.93 + power * 0.07
        holdoff = max(0, holdoff - dt)
        let s = max(0.1, min(2.0, sensitivity))
        let threshold = max(0.04, baseline * mult / s)
        if holdoff <= 0 && power > threshold {
            holdoff = refractory
            return true
        }
        return false
    }
}

private struct WaveEntity {
    var pos: Float       // pixel position
    var color: Float     // palette position 0..1
    var life: Float      // 0..1, fades as it travels
    var direction: Float // +1 or -1
}

private struct Ripple {
    var center: Float    // pixel position
    var radius: Float    // current radius
    var life: Float      // 0..1
    var color: Float     // palette position
}

private struct Twinkle {
    var pos: Int
    var color: Float
    var life: Float
}

/// Effect rendering and wire serialization. Render happens once into a
/// device-local logical buffer sized to the longest segment; serialize
/// fans the buffer out to each physical segment, applying its reverse +
/// in-segment mirror transforms.
final class Mapper {
    static let availableEffects: [String] = [
        "test",
        "solid",
        "rainbow",
        "breathe",
        "comet",
        "plasma",
        "spectrum",
        "wavelength",
        "beat_wave",
        "ripple",
        "glitter",
    ]

    static let reactiveEffects: [String] = [
        "spectrum", "wavelength", "beat_wave", "ripple", "glitter",
    ]

    static let ambientEffects: [String] = [
        "rainbow", "breathe", "comet", "plasma", "solid", "test",
    ]

    /// True for effects that do not need audio input (idle / ambient
    /// loops). Engine keeps these ticking even on silence or when the
    /// FFT window is not yet full.
    static func isAmbient(_ id: String) -> Bool {
        ambientEffects.contains(id)
    }

    static func pretty(_ id: String) -> String {
        switch id {
        case "test":       return "Test · R/G/B/W"
        case "solid":      return "Solid"
        case "rainbow":    return "Rainbow"
        case "breathe":    return "Breathe"
        case "comet":      return "Comet"
        case "plasma":     return "Plasma"
        case "spectrum":   return "Spectrum · Bars"
        case "wavelength": return "Wavelength"
        case "beat_wave":  return "Beat Wave"
        case "ripple":     return "Ripple"
        case "glitter":    return "Glitter"
        default:           return id
        }
    }

    let totalPixels: Int
    let rgbw: Bool
    var effect: String
    var palette: Palette = .sunset
    var speed: Float = 1.0
    var intensity: Float = 1.0
    var brightness: Float = 1.0
    var minLoad: Float = 0
    var segments: [SegmentRuntime]
    private(set) var pixels: [Pixel]

    private var renderLen: Int
    private var phase: Float = 0
    private var testPhase: Float = 0
    private var smoothPower: Float = 0
    private var beat = BeatDetector()
    private var peakHolds: [Float] = []
    private var waves: [WaveEntity] = []
    private var ripples: [Ripple] = []
    private var twinkles: [Twinkle] = []
    private var rng: UInt64 = 0xC2B2AE3D27D4EB4F

    private var lastEffect: String = ""
    private var lastPaletteID: String = ""
    private var transitionFrom: [Pixel] = []
    private var transitionT: Float = 1.0
    private let transitionDur: Float = 0.6

    private var plasmaPhaseA: Float = 0
    private var plasmaPhaseB: Float = 0

    private var wireBuf: [Pixel] = []
    private var byteBuf: [UInt8] = []

    init(totalPixels: Int, rgbw: Bool, effect: String, segments: [SegmentRuntime]) {
        self.totalPixels = totalPixels
        self.rgbw = rgbw
        self.effect = effect
        self.segments = segments
        let r = Mapper.computeRenderLen(segments, fallback: totalPixels)
        self.renderLen = r
        self.pixels = Array(repeating: .off, count: r)
        self.lastEffect = effect
        self.lastPaletteID = palette.id
        self.wireBuf = [Pixel](repeating: .off, count: totalPixels)
        self.byteBuf = [UInt8](repeating: 0, count: totalPixels * (rgbw ? 4 : 3))
    }

    private static func computeRenderLen(_ segments: [SegmentRuntime], fallback: Int) -> Int {
        let lens = segments.map { $0.length }
        return max(lens.max() ?? fallback, 1)
    }

    func updateSegments(_ s: [SegmentRuntime]) {
        if s == segments { return }
        segments = s
        let r = Mapper.computeRenderLen(s, fallback: totalPixels)
        if r != renderLen {
            renderLen = r
            pixels = Array(repeating: .off, count: r)
            peakHolds = []
            waves.removeAll()
            ripples.removeAll()
            twinkles.removeAll()
        }
    }

    func render(bands: [Float], power: Float, dt: Float) {
        let adt = dt * max(0.05, speed)
        if effect != lastEffect || palette.id != lastPaletteID {
            transitionFrom = pixels
            transitionT = 0
            lastEffect = effect
            lastPaletteID = palette.id
        }
        switch effect {
        case "test":       renderTest(dt: dt)
        case "solid":      renderSolid(power: power, dt: adt)
        case "rainbow":    renderRainbow(dt: adt)
        case "breathe":    renderBreathe(dt: adt)
        case "comet":      renderComet(dt: adt)
        case "plasma":     renderPlasma(power: power, dt: adt)
        case "spectrum":   renderSpectrum(bands: bands, dt: adt)
        case "wavelength": renderWavelength(bands: bands, dt: adt)
        case "beat_wave":  renderBeatWave(power: power, dt: adt)
        case "ripple":     renderRipple(power: power, dt: adt)
        case "glitter":    renderGlitter(bands: bands, power: power, dt: adt)
        default:           renderSpectrum(bands: bands, dt: adt)
        }
        applyTransitionCrossfade(dt: dt)
    }

    /// Smoothstep ease applied to a (transitionT / transitionDur) ramp,
    /// blending each pixel from the snapshot taken at the change moment
    /// toward the freshly-rendered frame. Avoids the harsh "snap" you
    /// otherwise get when the user switches effect or palette.
    private func applyTransitionCrossfade(dt: Float) {
        guard transitionT < transitionDur,
              transitionFrom.count == pixels.count,
              !pixels.isEmpty else { return }
        transitionT = min(transitionDur, transitionT + dt)
        let x = transitionT / transitionDur
        let xe = x * x * (3 - 2 * x)
        let inv = 1 - xe
        for i in 0..<pixels.count {
            let a = transitionFrom[i]
            let b = pixels[i]
            pixels[i] = Pixel(
                r: UInt8(clamping: Int((Float(a.r) * inv) + (Float(b.r) * xe))),
                g: UInt8(clamping: Int((Float(a.g) * inv) + (Float(b.g) * xe))),
                b: UInt8(clamping: Int((Float(a.b) * inv) + (Float(b.b) * xe))),
                w: UInt8(clamping: Int((Float(a.w) * inv) + (Float(b.w) * xe)))
            )
        }
    }

    func serialize(into out: inout [UInt8]) {
        out.removeAll(keepingCapacity: true)
        let bytesPerPixel = rgbw ? 4 : 3
        for i in 0..<totalPixels { wireBuf[i] = .off }
        for seg in segments {
            let s = max(0, seg.start)
            let len = max(0, min(seg.length, totalPixels - s))
            guard len > 0 else { continue }
            let halfPoint = seg.mirror ? (len + 1) / 2 : len
            for i in 0..<len {
                let srcLocal = (seg.mirror && i >= halfPoint) ? (len - 1 - i) : i
                let srcIdx = min(srcLocal, renderLen - 1)
                let dstLocal = seg.reverse ? (len - 1 - i) : i
                wireBuf[s + dstLocal] = pixels[srcIdx]
            }
        }
        out.reserveCapacity(totalPixels * bytesPerPixel)
        let b = max(0, min(1, brightness))
        let floorFrac = max(0, min(0.5, minLoad))
        @inline(__always) func scale(_ v: UInt8) -> UInt8 { UInt8(Float(v) * b) }

        // Two-stage PSU load floor.
        // Stage A: any all-dark pixel is filled with a palette-midpoint
        //          colour so it contributes some current.
        // Stage B: if the total channel sum is still below the target
        //          (floorFrac × maxPossibleSum), all pixels get a global
        //          gain — boosting brightness AND apparent saturation
        //          (dim colours brighten faster than already-bright ones).
        let fallback = palette.sample(at: 0.5)
        let dimByte = UInt8(min(255, floorFrac * 255))

        var idx = 0
        var sumF: Float = 0
        for p in wireBuf {
            var r  = scale(p.r)
            var g  = scale(p.g)
            var bl = scale(p.b)
            var w  = scale(p.w)
            if floorFrac > 0 && max(r, g, bl, w) == 0 {
                if rgbw {
                    w = dimByte
                } else {
                    r  = UInt8(min(255, fallback.r * Float(dimByte)))
                    g  = UInt8(min(255, fallback.g * Float(dimByte)))
                    bl = UInt8(min(255, fallback.b * Float(dimByte)))
                }
            }
            byteBuf[idx] = r;  idx += 1
            byteBuf[idx] = g;  idx += 1
            byteBuf[idx] = bl; idx += 1
            sumF += Float(r) + Float(g) + Float(bl)
            if rgbw { byteBuf[idx] = w; idx += 1; sumF += Float(w) }
        }

        if floorFrac > 0 {
            let target = floorFrac * Float(totalPixels * bytesPerPixel) * 255
            if sumF < target {
                let gain = min(4.0, target / max(sumF, 1))
                for j in 0..<byteBuf.count {
                    byteBuf[j] = UInt8(min(255, Float(byteBuf[j]) * gain))
                }
            }
        }

        out.append(contentsOf: byteBuf)
    }

    func writeBlack(into out: inout [UInt8]) {
        let bytesPerPixel = rgbw ? 4 : 3
        out = [UInt8](repeating: 0, count: totalPixels * bytesPerPixel)
    }

    func writeSolid(_ pixel: Pixel, into out: inout [UInt8]) {
        let bytesPerPixel = rgbw ? 4 : 3
        out.removeAll(keepingCapacity: true)
        out.reserveCapacity(totalPixels * bytesPerPixel)
        let b = max(0, min(1, brightness))
        @inline(__always) func scale(_ v: UInt8) -> UInt8 { UInt8(Float(v) * b) }
        for _ in 0..<totalPixels {
            out.append(scale(pixel.r)); out.append(scale(pixel.g)); out.append(scale(pixel.b))
            if rgbw { out.append(scale(pixel.w)) }
        }
    }

    // MARK: - Effects

    private func renderTest(dt: Float) {
        testPhase += dt
        if testPhase > 4 { testPhase -= 4 }
        let phase = Int(testPhase)
        let p: Pixel
        switch phase {
        case 0: p = Pixel(r: 255, g: 0,   b: 0,   w: 0)
        case 1: p = Pixel(r: 0,   g: 255, b: 0,   w: 0)
        case 2: p = Pixel(r: 0,   g: 0,   b: 255, w: 0)
        default: p = Pixel(r: 255, g: 255, b: 255, w: 0)
        }
        for i in 0..<renderLen { pixels[i] = p }
    }

    /// Ambient: smooth crossfade of one palette colour across the whole
    /// strip + sinusoidal brightness pulse. Calm "lung" feel. No audio.
    private func renderBreathe(dt: Float) {
        phase += dt * 0.05
        if phase >= 1 { phase -= 1 }
        let breath = 0.5 + 0.5 * sin(phase * 2 * .pi)
        let c = paletteSeamless(at: phase)
        let v = 0.20 + 0.65 * breath * max(0.4, min(1.5, intensity))
        let bright = max(0.05, min(1.0, v))
        let p = Pixel.fromRGB(c.r, c.g, c.b, v: bright, rgbw: rgbw)
        for i in 0..<renderLen { pixels[i] = p }
    }

    /// Ambient: head pixel drifts across the strip with a fading tail.
    /// Head colour walks the palette. `speed` already baked into `dt`.
    private func renderComet(dt: Float) {
        phase += dt * 0.22
        if phase >= 1 { phase -= 1 }
        let n = max(1, renderLen)
        let head = phase * Float(n)
        let tailLen = max(4, Float(n) * 0.18 * max(0.6, min(1.6, intensity)))
        let c = paletteSeamless(at: phase)
        for i in 0..<n {
            let d = Float(i) - head
            let along = d.truncatingRemainder(dividingBy: Float(n))
            let dist = abs(along < -Float(n) / 2 ? along + Float(n) : (along > Float(n) / 2 ? along - Float(n) : along))
            let t = max(0, 1 - dist / tailLen)
            let v = t * t
            pixels[i] = Pixel.fromRGB(c.r, c.g, c.b, v: v, rgbw: rgbw)
        }
    }

    /// Reactive-ambient hybrid: two sin waves at different spatial
    /// frequencies interfere and drive the palette index. Always drifts
    /// at a base ambient rate; intensity controls how strongly audio
    /// power accelerates the drift. RMS is compressed via sqrt so quiet
    /// passages still produce visible motion. At intensity 0 the effect
    /// is purely ambient; at intensity 2 each loud frame nearly maxes
    /// the boost. Both phase accumulators are independently wrapped at
    /// 2π so the pattern is fully cyclical with no seam.
    private func renderPlasma(power: Float, dt: Float) {
        let twoPi = 2 * Float.pi
        let p = max(0, min(1, sqrt(max(0, power) * 4)))
        let gain = max(0, min(2, intensity))
        let boost = 1 + gain * 8 * p
        plasmaPhaseA = (plasmaPhaseA + dt * 0.20 * twoPi * boost).truncatingRemainder(dividingBy: twoPi)
        plasmaPhaseB = (plasmaPhaseB + dt * 0.27 * twoPi * boost).truncatingRemainder(dividingBy: twoPi)
        let n = max(1, renderLen)
        let invN = twoPi / Float(n)
        let bright: Float = 0.75
        let kA: Float = 2
        let kB: Float = 1
        for i in 0..<n {
            let x = Float(i) * invN
            let a = sin(x * kA + plasmaPhaseA)
            let b = sin(x * kB - plasmaPhaseB)
            let t = 0.5 + 0.5 * (a + b) * 0.5
            let c = palette.sample(at: max(0, min(1, t)))
            pixels[i] = Pixel.fromRGB(c.r, c.g, c.b, v: bright, rgbw: rgbw)
        }
    }

    /// Passive: a full HSV rainbow wraps once around the strip and slowly
    /// scrolls, no audio input. `speed` controls drift rate; `intensity`
    /// stretches/compresses the visible cycles. Ignores the active palette
    /// so the rainbow is always the literal hue spectrum.
    private func renderRainbow(dt: Float) {
        phase += dt * 0.06
        if phase >= 1 { phase -= 1 }
        let n = max(1, renderLen)
        let cycles = 1.0 + 1.5 * max(0, intensity - 1.0)
        let invN = 1.0 / Float(n)
        let bright = max(0.3, min(1.0, 0.55 + 0.25 * intensity))
        for i in 0..<n {
            var t = Float(i) * invN * cycles + phase
            t -= floor(t)
            let (r, g, b) = hsvToRGB(h: t, s: 1, v: 1)
            pixels[i] = Pixel.fromRGB(r, g, b, v: bright, rgbw: rgbw)
        }
    }

    /// Sample the palette with a triangle-wave fold so consecutive cycles
    /// share endpoints — palette traverses 0→1→0 each period, eliminating
    /// the color jump at the phase wrap that an arbitrary (non-loop-closed)
    /// palette would otherwise show.
    private func paletteSeamless(at phase: Float) -> (r: Float, g: Float, b: Float) {
        let p = phase - floor(phase)
        let q = p < 0.5 ? p * 2 : (1 - p) * 2
        return palette.sample(at: max(0, min(1, q)))
    }

    /// Hue [0,1) → linear RGB [0,1]. Standard 6-segment HSV conversion.
    private func hsvToRGB(h: Float, s: Float, v: Float) -> (Float, Float, Float) {
        let hh = (h - floor(h)) * 6
        let i = Int(hh) % 6
        let f = hh - floor(hh)
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    /// Whole strip lit by the palette, hue position drifts with `speed`,
    /// brightness modulated by smoothed power × intensity. When called
    /// from ambient mode (power == 0) the brightness is floored so the
    /// strip stays visible on silence.
    private func renderSolid(power: Float, dt: Float) {
        let target = min(1.0, power * intensity * 5.0)
        smoothPower += (target - smoothPower) * min(1, dt * 5)
        let floor: Float = power < 0.0001 ? 0.45 : 0.05
        let v = max(floor, smoothPower)
        phase += dt * 0.08
        if phase > 1 { phase -= 1 }
        let c = paletteSeamless(at: phase)
        let p = Pixel.fromRGB(c.r, c.g, c.b, v: v, rgbw: rgbw)
        for i in 0..<renderLen { pixels[i] = p }
    }

    /// Divide the strip into N bars (each ~8 px), each bar lit
    /// proportional to the average amplitude of the bands assigned to
    /// it. Peak-hold dots fall under gravity controlled by `speed`.
    /// Palette colour gradient across bars (low→high freq).
    private func renderSpectrum(bands: [Float], dt: Float) {
        guard renderLen > 0, !bands.isEmpty else { return }
        // Aim for ~8 px per bar but at least 4 bars and at most `bands.count`.
        let nBars = max(4, min(bands.count, renderLen / 8))
        let pixelsPerBar = max(1, renderLen / nBars)
        if peakHolds.count != nBars { peakHolds = [Float](repeating: 0, count: nBars) }

        // Zero pixels each frame (no decay; bars fully redrawn).
        for i in 0..<renderLen { pixels[i] = .off }

        let gain = max(0.2, min(3.0, intensity * 1.6))
        let peakFallPerSec: Float = 1.2  // bar-fractions/sec
        for bi in 0..<nBars {
            let loBand = bi * bands.count / nBars
            let hiBand = (bi + 1) * bands.count / nBars
            let span = max(1, hiBand - loBand)
            var sum: Float = 0
            for j in 0..<span {
                let idx = min(bands.count - 1, loBand + j)
                sum += bands[idx]
            }
            let amp = max(0, min(1, sum / Float(span) * gain))
            peakHolds[bi] = max(peakHolds[bi] - dt * peakFallPerSec, amp)

            let barStart = bi * pixelsPerBar
            let barLast = min(renderLen, barStart + pixelsPerBar)
            let lit = Int(amp * Float(pixelsPerBar) + 0.5)
            let peakPx = min(pixelsPerBar - 1, Int(peakHolds[bi] * Float(pixelsPerBar) + 0.5))
            let colorPos = Float(bi) / Float(max(nBars - 1, 1))
            let c = palette.sample(at: colorPos)
            for p in barStart..<barLast {
                let local = p - barStart
                if local < lit {
                    pixels[p] = Pixel.fromRGB(c.r, c.g, c.b, v: 1.0, rgbw: rgbw)
                } else if local == peakPx && peakHolds[bi] > 0.02 {
                    pixels[p] = Pixel.fromRGB(c.r, c.g, c.b, v: 0.8, rgbw: rgbw)
                }
            }
        }
    }

    /// Per-pixel: palette colour scrolls across the strip at `speed`,
    /// brightness pulled from the band corresponding to that x position
    /// — bass on the left, treble on the right (or vice versa). Lots of
    /// motion, lots of colour.
    private func renderWavelength(bands: [Float], dt: Float) {
        guard renderLen > 0, !bands.isEmpty else { return }
        phase += dt * 0.15
        if phase > 1000 { phase -= 1000 }
        let gain = max(0.2, min(3.0, intensity * 1.5))
        let n = Float(max(renderLen - 1, 1))
        for i in 0..<renderLen {
            let f = Float(i) / n
            let bi = min(bands.count - 1, Int(f * Float(bands.count)))
            let v = max(0, min(1, bands[bi] * gain))
            let t = (f + phase).truncatingRemainder(dividingBy: 1)
            let c = paletteSeamless(at: t < 0 ? t + 1 : t)
            pixels[i] = Pixel.fromRGB(c.r, c.g, c.b, v: v, rgbw: rgbw)
        }
    }

    /// On each detected beat spawn a coloured wave that traverses the
    /// strip. `speed` scales traversal rate, `intensity` raises beat
    /// sensitivity. Tail of each wave fades as it travels.
    private func renderBeatWave(power: Float, dt: Float) {
        // BeatDetector uses real-time dt, not the speed-scaled one, so
        // beats track the music rather than the speed slider.
        let realDt = dt / max(0.05, speed)
        if beat.update(power: power, dt: realDt, sensitivity: intensity) {
            phase += 0.17
            if phase > 1 { phase -= 1 }
            let dir: Float = waves.count.isMultiple(of: 2) ? 1 : -1
            let start: Float = dir > 0 ? 0 : Float(renderLen - 1)
            waves.append(WaveEntity(pos: start, color: phase, life: 1.0, direction: dir))
            if waves.count > 6 { waves.removeFirst(waves.count - 6) }
        }

        let traverse: Float = Float(renderLen) * 0.9
        for i in waves.indices {
            waves[i].pos += dt * traverse * waves[i].direction
            waves[i].life -= dt * 0.4
        }
        waves.removeAll { $0.life <= 0 || $0.pos < -10 || $0.pos > Float(renderLen) + 10 }

        // Faint palette gradient base so the strip never goes fully dark.
        let nn = Float(max(renderLen - 1, 1))
        for i in 0..<renderLen {
            let c = palette.sample(at: Float(i) / nn)
            pixels[i] = Pixel.fromRGB(c.r, c.g, c.b, v: 0.06, rgbw: rgbw)
        }
        for w in waves {
            let center = Int(w.pos)
            let c = palette.sample(at: w.color)
            // 9-pixel gaussian-ish kernel.
            for offset in -4...4 {
                let idx = center + offset
                guard idx >= 0 && idx < renderLen else { continue }
                let falloff = expf(-Float(offset * offset) * 0.4)
                let v = max(0, min(1, w.life * falloff))
                let prev = pixels[idx]
                let add = Pixel.fromRGB(c.r, c.g, c.b, v: v, rgbw: rgbw)
                pixels[idx] = addPixels(prev, add)
            }
        }
    }

    /// Bass kick spawns a ripple radiating from the centre. Each ripple
    /// expands at `speed`, fading as it grows. Palette cycles per ripple.
    private func renderRipple(power: Float, dt: Float) {
        let realDt = dt / max(0.05, speed)
        if beat.update(power: power, dt: realDt, sensitivity: intensity) {
            phase += 0.13
            if phase > 1 { phase -= 1 }
            ripples.append(Ripple(center: Float(renderLen) * 0.5, radius: 0, life: 1.0, color: phase))
            if ripples.count > 5 { ripples.removeFirst(ripples.count - 5) }
        }

        let expandRate: Float = Float(renderLen) * 0.5
        for i in ripples.indices {
            ripples[i].radius += dt * expandRate
            ripples[i].life -= dt * 0.5
        }
        ripples.removeAll { $0.life <= 0 || $0.radius > Float(renderLen) }

        for i in 0..<renderLen { pixels[i] = .off }
        for rip in ripples {
            let c = palette.sample(at: rip.color)
            let ring = rip.radius
            for offset in -3...3 {
                let dist = ring + Float(offset)
                if dist < 0 { continue }
                let leftIdx = Int(rip.center - dist)
                let rightIdx = Int(rip.center + dist)
                let falloff = expf(-Float(offset * offset) * 0.3)
                let v = max(0, min(1, rip.life * falloff))
                if leftIdx >= 0 && leftIdx < renderLen {
                    pixels[leftIdx] = addPixels(pixels[leftIdx], Pixel.fromRGB(c.r, c.g, c.b, v: v, rgbw: rgbw))
                }
                if rightIdx >= 0 && rightIdx < renderLen && rightIdx != leftIdx {
                    pixels[rightIdx] = addPixels(pixels[rightIdx], Pixel.fromRGB(c.r, c.g, c.b, v: v, rgbw: rgbw))
                }
            }
        }
    }

    /// Palette gradient base + twinkles overlaid wherever the high
    /// bands light up. Each twinkle is a pixel that flashes in palette
    /// colour and fades. `speed` shortens twinkle lifetime (faster
    /// flicker); `intensity` raises spawn rate.
    private func renderGlitter(bands: [Float], power: Float, dt: Float) {
        guard renderLen > 0 else { return }
        // Base gradient — palette across strip dimmed.
        let nn = Float(max(renderLen - 1, 1))
        let base: Float = 0.18 + min(0.30, power * intensity * 1.5)
        for i in 0..<renderLen {
            let c = palette.sample(at: Float(i) / nn)
            pixels[i] = Pixel.fromRGB(c.r, c.g, c.b, v: base, rgbw: rgbw)
        }

        // Decay existing twinkles.
        let decay: Float = 2.5
        for i in twinkles.indices { twinkles[i].life -= dt * decay }
        twinkles.removeAll { $0.life <= 0 }

        // Spawn new twinkles biased to higher bands. Density tracks
        // power × intensity; one fresh attempt per frame per ~3 pixels.
        let attemptsPerSec: Float = Float(renderLen) * 0.5 * max(0.3, intensity)
        let attempts = Int(attemptsPerSec * dt) + 1
        let highCutoff = bands.count / 2
        var highEnergy: Float = 0
        if bands.count > highCutoff {
            for i in highCutoff..<bands.count { highEnergy += bands[i] }
            highEnergy /= Float(bands.count - highCutoff)
        }
        let spawnProb = max(0, min(1, highEnergy * 4.0 * intensity))
        for _ in 0..<attempts {
            if Float(nextRand()) / Float(UInt32.max) < spawnProb {
                let pos = Int(nextRand() % UInt32(renderLen))
                let color = Float(nextRand()) / Float(UInt32.max)
                twinkles.append(Twinkle(pos: pos, color: color, life: 1.0))
                if twinkles.count > renderLen { twinkles.removeFirst(twinkles.count - renderLen) }
            }
        }

        for t in twinkles {
            guard t.pos >= 0 && t.pos < renderLen else { continue }
            let c = palette.sample(at: t.color)
            let v = max(0, min(1, t.life))
            pixels[t.pos] = addPixels(pixels[t.pos], Pixel.fromRGB(c.r, c.g, c.b, v: v, rgbw: rgbw))
        }
    }

    // MARK: - Pixel helpers

    @inline(__always) private func addPixels(_ a: Pixel, _ b: Pixel) -> Pixel {
        Pixel(
            r: UInt8(clamping: Int(a.r) + Int(b.r)),
            g: UInt8(clamping: Int(a.g) + Int(b.g)),
            b: UInt8(clamping: Int(a.b) + Int(b.b)),
            w: UInt8(clamping: Int(a.w) + Int(b.w))
        )
    }

    @inline(__always) private func nextRand() -> UInt32 {
        rng ^= rng << 13
        rng ^= rng >> 7
        rng ^= rng << 17
        return UInt32(truncatingIfNeeded: rng)
    }
}
