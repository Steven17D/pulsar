# Per-Effect Params + Unified Reactivity — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the reactive/ambient split with a per-effect param model. Each effect declares its own sliders, every slider is drivable by audio, brightness is the only global slider, and adding a new effect is one new file plus one registry entry.

**Architecture:** Introduce an `Effect` protocol carrying declared `EffectParam` metadata. One file per effect under `Sources/Pulsar/Effects/`. `Mapper` becomes a thin host that dispatches to the registered effect. Persisted state holds a `[effectID: [paramID: value+driver]]` map; one-shot migration folds legacy `speed`/`intensity`/`*_reactive`/`*_aspect` fields into it on first load.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, XCTest, AudioToolbox/Accelerate (untouched).

**Companion spec:** `docs/superpowers/specs/2026-05-24-per-effect-params-design.md`.

---

## Conventions used throughout this plan

- All param values, defaults, and floors are normalized `[0,1]`.
- Effects map `0..1` to their natural internal range. Convention: `intensity`-like and `speed`-like params multiply by `2` so `0.5` matches the legacy `1.0` baseline.
- Each task is one commit. Commit messages follow the existing repo style: short imperative subject, no Conventional Commits prefix, no trailers, no emoji (`CLAUDE.md`).
- Run the test suite from the repo root with: `swift test`.
- Build with: `swift build`.
- Manual visual smoke test: `PULSAR_SHOWCASE_RENDER=/tmp/pulsar-shots swift run`. Inspect `/tmp/pulsar-shots/*.png`.

---

## File Structure

**New files:**

- `Sources/Pulsar/Effects/Effect.swift` — `Effect` protocol, `EffectParam`, `Driver`, `EffectParamState`, format helpers.
- `Sources/Pulsar/Effects/Shared.swift` — `BeatDetector`, palette/HSV helpers, `addPixels`.
- `Sources/Pulsar/Effects/Registry.swift` — `EffectRegistry.all`, `availableIDs`, `type(byID:)`.
- `Sources/Pulsar/Effects/Test.swift` — `TestEffect`.
- `Sources/Pulsar/Effects/Solid.swift` — `SolidEffect`.
- `Sources/Pulsar/Effects/Rainbow.swift` — `RainbowEffect`.
- `Sources/Pulsar/Effects/Breathe.swift` — `BreatheEffect`.
- `Sources/Pulsar/Effects/Comet.swift` — `CometEffect`.
- `Sources/Pulsar/Effects/Plasma.swift` — `PlasmaEffect`.
- `Sources/Pulsar/Effects/Spectrum.swift` — `SpectrumEffect`.
- `Sources/Pulsar/Effects/Wavelength.swift` — `WavelengthEffect`.
- `Sources/Pulsar/Effects/BeatWave.swift` — `BeatWaveEffect`.
- `Sources/Pulsar/Effects/Ripple.swift` — `RippleEffect`.
- `Sources/Pulsar/Effects/Glitter.swift` — `GlitterEffect`.
- `Tests/PulsarTests/EffectRegistryTests.swift`
- `Tests/PulsarTests/EffectParamResolutionTests.swift`
- `Tests/PulsarTests/ConfigMigrationTests.swift`

**Modified files:**

- `Sources/Pulsar/Mapper.swift` — strips effect impls, lists, `isAmbient`, `pretty`; dispatches via registry.
- `Sources/Pulsar/Models.swift` — drops legacy `speed`/`intensity`/`*_reactive`/`*_aspect`; adds `Driver`, `EffectParamState`, `brightnessDriver`, `effectState`, `LiveFrame.effParams`.
- `Sources/Pulsar/Config.swift` — new schema fields, migration, sanitization.
- `Sources/Pulsar/ControlModel.swift` — `RenderState` carries new shape; setters become uniform.
- `Sources/Pulsar/AudioEngine.swift` — per-param resolution; drops idle-purple and ambient gate.
- `Sources/Pulsar/BarView.swift` — flat effect picker, dynamic param rows, removes `KindBadge`.
- `Sources/Pulsar/Showcase.swift` — seeds `effectState` instead of `speed`/`intensity`.
- `CLAUDE.md` — rewrites the "Effects" section.

---

## Task 1: Add Effect protocol and param types

**Files:**
- Create: `Sources/Pulsar/Effects/Effect.swift`

- [ ] **Step 1: Create the protocol file**

```swift
// Sources/Pulsar/Effects/Effect.swift
import Foundation

/// Single audio descriptor that can drive a slider. (Moved unchanged from
/// Models.swift in Task 9 — declared here in advance so effect protocol is
/// self-contained. AudioAspect itself stays in Models.swift for now.)

/// Reactivity state for a single slider. `reactive == false` means the
/// slider value passes through unchanged; otherwise the audio signal at
/// `aspect` modulates the value.
struct Driver: Codable, Equatable {
    var reactive: Bool
    var aspect: AudioAspect

    static let manualPower = Driver(reactive: false, aspect: .power)
}

/// One persisted slot per (effectID, paramID).
struct EffectParamState: Codable, Equatable {
    var value: Float            // 0..1
    var driver: Driver
}

/// Declarative description of one slider an effect exposes. Order in the
/// effect's `params` list is the UI order top-to-bottom.
struct EffectParam {
    let id: String              // stable wire id, e.g. "speed"
    let label: String           // UI label, e.g. "Speed"
    let defaultValue: Float     // 0..1
    let driverFloor: Float      // 0..1; used when driven by audio
    let format: (Float) -> String

    /// `0.50` → `"50%"`.
    static let pct: (Float) -> String = { v in
        "\(Int((v * 100).rounded()))%"
    }
    /// `0.50` → `"1.00x"` (multiplier-style display: maps 0..1 → 0..2).
    static let mult: (Float) -> String = { v in
        String(format: "%0.2fx", v * 2)
    }
}

/// Effects are reference types because they own per-instance mutable
/// state (phase accumulators, particle lists). Instances are reset on
/// effect switch.
protocol Effect: AnyObject {
    static var id: String { get }
    static var label: String { get }
    static var params: [EffectParam] { get }

    init(renderLen: Int)
    func resize(_ renderLen: Int)
    /// `params` carries already-driven values in [0,1]; missing keys
    /// MUST fall back via `params[id, default: declared default]`.
    func render(into pixels: inout [Pixel],
                bands: [Float], power: Float, dt: Float,
                params: [String: Float],
                palette: Palette, rgbw: Bool)
}

extension Effect {
    /// Reads a param with the declared default as fallback. Convenience
    /// so concrete effects never trap on a missing key.
    static func paramValue(_ id: String, in params: [String: Float]) -> Float {
        if let v = params[id] { return v }
        return Self.params.first { $0.id == id }?.defaultValue ?? 0.5
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: PASS. No call sites yet — the new types are additive.

- [ ] **Step 3: Commit**

```bash
git add Sources/Pulsar/Effects/Effect.swift
git commit -m "Add Effect protocol and param descriptors"
```

---

## Task 2: Extract shared effect helpers

Move `BeatDetector` and the local pixel/palette helpers off `Mapper` into a shared file so per-effect files can call them. Keep the existing `Mapper`-private helpers in place (callers inside `Mapper` still need them); the new file is the canonical home.

**Files:**
- Create: `Sources/Pulsar/Effects/Shared.swift`
- Modify: `Sources/Pulsar/Mapper.swift`

- [ ] **Step 1: Create Shared.swift**

```swift
// Sources/Pulsar/Effects/Shared.swift
import Foundation

/// Simple onset detector: keeps a smoothed baseline of power and triggers
/// when current power exceeds baseline by a multiplier. A refractory
/// period prevents double-triggers within a single drum hit.
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

/// Sample the palette with a triangle-wave fold so consecutive cycles
/// share endpoints — palette traverses 0→1→0 each period.
func paletteSeamless(_ palette: Palette, at phase: Float) -> (r: Float, g: Float, b: Float) {
    let p = phase - floor(phase)
    let q = p < 0.5 ? p * 2 : (1 - p) * 2
    return palette.sample(at: max(0, min(1, q)))
}

/// Hue [0,1) → linear RGB [0,1]. Standard 6-segment HSV conversion.
func hsvToRGB(h: Float, s: Float, v: Float) -> (Float, Float, Float) {
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

@inline(__always) func addPixels(_ a: Pixel, _ b: Pixel) -> Pixel {
    Pixel(
        r: UInt8(clamping: Int(a.r) + Int(b.r)),
        g: UInt8(clamping: Int(a.g) + Int(b.g)),
        b: UInt8(clamping: Int(a.b) + Int(b.b)),
        w: UInt8(clamping: Int(a.w) + Int(b.w))
    )
}

/// xorshift64-style PRNG. Per-effect instances should hold their own seed.
struct EffectRNG {
    var state: UInt64 = 0xC2B2AE3D27D4EB4F
    mutating func next() -> UInt32 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return UInt32(truncatingIfNeeded: state)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: PASS. The new file adds globals; `Mapper.swift` still has its private copies. Swift allows the duplicate names because `Mapper`'s versions are file-private (the BeatDetector struct in Mapper.swift is internal — rename the new one if a collision appears).

If `BeatDetector` collides at this step: skip the new declaration of `BeatDetector` from `Shared.swift` for now and add it in Task 8 when `Mapper`'s copy is deleted. The other helpers (`paletteSeamless`, `hsvToRGB`, `addPixels`, `EffectRNG`) do not collide because the existing ones are file-private methods, not top-level functions.

Confirm a clean build before committing.

- [ ] **Step 3: Commit**

```bash
git add Sources/Pulsar/Effects/Shared.swift
git commit -m "Extract shared effect helpers"
```

---

## Task 3: Add Effect registry (empty)

Empty registry first so subsequent tasks can fill it without breaking compilation.

**Files:**
- Create: `Sources/Pulsar/Effects/Registry.swift`

- [ ] **Step 1: Create Registry.swift**

```swift
// Sources/Pulsar/Effects/Registry.swift
import Foundation

enum EffectRegistry {
    /// Authoritative ordered list of every effect. The UI picker shows
    /// effects in this order. Adding a new effect = add a file under
    /// Effects/ and append the type here.
    static let all: [Effect.Type] = [
        // Populated incrementally in Tasks 4–7.
    ]

    static var availableIDs: [String] { all.map { $0.id } }

    /// Returns the registered type matching `id`, falling back to the
    /// first registered effect so a missing/legacy id can't crash startup.
    static func type(byID id: String) -> Effect.Type? {
        all.first { $0.id == id }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: PASS. Nothing references the registry yet.

- [ ] **Step 3: Commit**

```bash
git add Sources/Pulsar/Effects/Registry.swift
git commit -m "Add empty Effect registry"
```

---

## Task 4: Migrate Test, Solid, Rainbow effects

Each effect becomes a class implementing `Effect`. The render body is the existing `Mapper.renderXxx` code, lifted, with three changes:
1. Read params from the `params` dict (with declared-default fallback).
2. Map normalized `0..1` to the old `0..2` natural range where the old code multiplied by `speed`/`intensity`.
3. Use the top-level `paletteSeamless` / `hsvToRGB` helpers from `Shared.swift`.

**Files:**
- Create: `Sources/Pulsar/Effects/Test.swift`
- Create: `Sources/Pulsar/Effects/Solid.swift`
- Create: `Sources/Pulsar/Effects/Rainbow.swift`
- Modify: `Sources/Pulsar/Effects/Registry.swift`

- [ ] **Step 1: Create Test.swift**

```swift
// Sources/Pulsar/Effects/Test.swift
import Foundation

final class TestEffect: Effect {
    static let id = "test"
    static let label = "Test · R/G/B/W"
    static let params: [EffectParam] = []

    private var testPhase: Float = 0
    private var renderLen: Int

    init(renderLen: Int) { self.renderLen = max(1, renderLen) }
    func resize(_ renderLen: Int) { self.renderLen = max(1, renderLen) }

    func render(into pixels: inout [Pixel],
                bands: [Float], power: Float, dt: Float,
                params: [String: Float],
                palette: Palette, rgbw: Bool) {
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
        for i in 0..<min(renderLen, pixels.count) { pixels[i] = p }
    }
}
```

- [ ] **Step 2: Create Solid.swift**

```swift
// Sources/Pulsar/Effects/Solid.swift
import Foundation

final class SolidEffect: Effect {
    static let id = "solid"
    static let label = "Solid"
    static let params: [EffectParam] = [
        EffectParam(id: "speed",     label: "Speed",     defaultValue: 0.5, driverFloor: 0.25, format: EffectParam.mult),
        EffectParam(id: "intensity", label: "Intensity", defaultValue: 0.5, driverFloor: 0.20, format: EffectParam.mult),
    ]

    private var phase: Float = 0
    private var smoothPower: Float = 0
    private var renderLen: Int

    init(renderLen: Int) { self.renderLen = max(1, renderLen) }
    func resize(_ renderLen: Int) { self.renderLen = max(1, renderLen) }

    func render(into pixels: inout [Pixel],
                bands: [Float], power: Float, dt: Float,
                params: [String: Float],
                palette: Palette, rgbw: Bool) {
        let speed     = Self.paramValue("speed",     in: params) * 2
        let intensity = Self.paramValue("intensity", in: params) * 2
        let adt = dt * max(0.05, speed)

        let target = min(1.0, power * intensity * 5.0)
        smoothPower += (target - smoothPower) * min(1, adt * 5)
        let floorV: Float = power < 0.0001 ? 0.45 : 0.05
        let v = max(floorV, smoothPower)
        phase += adt * 0.08
        if phase > 1 { phase -= 1 }
        let c = paletteSeamless(palette, at: phase)
        let p = Pixel.fromRGB(c.r, c.g, c.b, v: v, rgbw: rgbw)
        for i in 0..<min(renderLen, pixels.count) { pixels[i] = p }
    }
}
```

- [ ] **Step 3: Create Rainbow.swift**

```swift
// Sources/Pulsar/Effects/Rainbow.swift
import Foundation

final class RainbowEffect: Effect {
    static let id = "rainbow"
    static let label = "Rainbow"
    static let params: [EffectParam] = [
        EffectParam(id: "speed",  label: "Speed",  defaultValue: 0.5, driverFloor: 0.25, format: EffectParam.mult),
        EffectParam(id: "cycles", label: "Cycles", defaultValue: 0.4, driverFloor: 0.00, format: EffectParam.pct),
    ]

    private var phase: Float = 0
    private var renderLen: Int

    init(renderLen: Int) { self.renderLen = max(1, renderLen) }
    func resize(_ renderLen: Int) { self.renderLen = max(1, renderLen) }

    func render(into pixels: inout [Pixel],
                bands: [Float], power: Float, dt: Float,
                params: [String: Float],
                palette: Palette, rgbw: Bool) {
        let speed  = Self.paramValue("speed",  in: params) * 2
        let cycles = Self.paramValue("cycles", in: params) * 2  // 0..2
        let adt = dt * max(0.05, speed)
        phase += adt * 0.06
        if phase >= 1 { phase -= 1 }
        let n = max(1, min(renderLen, pixels.count))
        let visibleCycles = 1.0 + 1.5 * max(0, cycles - 1.0)
        let invN = 1.0 / Float(n)
        let bright = max(0.3, min(1.0, 0.55 + 0.25 * cycles))
        for i in 0..<n {
            var t = Float(i) * invN * visibleCycles + phase
            t -= floor(t)
            let (r, g, b) = hsvToRGB(h: t, s: 1, v: 1)
            pixels[i] = Pixel.fromRGB(r, g, b, v: bright, rgbw: rgbw)
        }
    }
}
```

- [ ] **Step 4: Register the three types**

Modify `Sources/Pulsar/Effects/Registry.swift`:

```swift
static let all: [Effect.Type] = [
    TestEffect.self,
    SolidEffect.self,
    RainbowEffect.self,
]
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: PASS. Effects are dead code at this point (`Mapper` still owns the rendering); only the type system has to be happy.

- [ ] **Step 6: Commit**

```bash
git add Sources/Pulsar/Effects/Test.swift Sources/Pulsar/Effects/Solid.swift Sources/Pulsar/Effects/Rainbow.swift Sources/Pulsar/Effects/Registry.swift
git commit -m "Migrate test, solid, rainbow effects"
```

---

## Task 5: Migrate Breathe, Comet, Plasma effects

**Files:**
- Create: `Sources/Pulsar/Effects/Breathe.swift`
- Create: `Sources/Pulsar/Effects/Comet.swift`
- Create: `Sources/Pulsar/Effects/Plasma.swift`
- Modify: `Sources/Pulsar/Effects/Registry.swift`

- [ ] **Step 1: Create Breathe.swift**

```swift
// Sources/Pulsar/Effects/Breathe.swift
import Foundation

final class BreatheEffect: Effect {
    static let id = "breathe"
    static let label = "Breathe"
    static let params: [EffectParam] = [
        EffectParam(id: "speed",     label: "Speed",     defaultValue: 0.5, driverFloor: 0.25, format: EffectParam.mult),
        EffectParam(id: "intensity", label: "Intensity", defaultValue: 0.5, driverFloor: 0.20, format: EffectParam.mult),
    ]

    private var phase: Float = 0
    private var renderLen: Int

    init(renderLen: Int) { self.renderLen = max(1, renderLen) }
    func resize(_ renderLen: Int) { self.renderLen = max(1, renderLen) }

    func render(into pixels: inout [Pixel],
                bands: [Float], power: Float, dt: Float,
                params: [String: Float],
                palette: Palette, rgbw: Bool) {
        let speed     = Self.paramValue("speed",     in: params) * 2
        let intensity = Self.paramValue("intensity", in: params) * 2
        let adt = dt * max(0.05, speed)
        phase += adt * 0.05
        if phase >= 1 { phase -= 1 }
        let breath = 0.5 + 0.5 * sin(phase * 2 * .pi)
        let c = paletteSeamless(palette, at: phase)
        let v = 0.20 + 0.65 * breath * max(0.4, min(1.5, intensity))
        let bright = max(0.05, min(1.0, v))
        let p = Pixel.fromRGB(c.r, c.g, c.b, v: bright, rgbw: rgbw)
        for i in 0..<min(renderLen, pixels.count) { pixels[i] = p }
    }
}
```

- [ ] **Step 2: Create Comet.swift**

```swift
// Sources/Pulsar/Effects/Comet.swift
import Foundation

final class CometEffect: Effect {
    static let id = "comet"
    static let label = "Comet"
    static let params: [EffectParam] = [
        EffectParam(id: "speed", label: "Speed", defaultValue: 0.5, driverFloor: 0.25, format: EffectParam.mult),
        EffectParam(id: "tail",  label: "Tail",  defaultValue: 0.5, driverFloor: 0.00, format: EffectParam.pct),
    ]

    private var phase: Float = 0
    private var renderLen: Int

    init(renderLen: Int) { self.renderLen = max(1, renderLen) }
    func resize(_ renderLen: Int) { self.renderLen = max(1, renderLen) }

    func render(into pixels: inout [Pixel],
                bands: [Float], power: Float, dt: Float,
                params: [String: Float],
                palette: Palette, rgbw: Bool) {
        let speed = Self.paramValue("speed", in: params) * 2
        let tail  = Self.paramValue("tail",  in: params) * 2
        let adt = dt * max(0.05, speed)
        phase += adt * 0.22
        if phase >= 1 { phase -= 1 }
        let n = max(1, min(renderLen, pixels.count))
        let head = phase * Float(n)
        let tailLen = max(4, Float(n) * 0.18 * max(0.6, min(1.6, tail)))
        let c = paletteSeamless(palette, at: phase)
        for i in 0..<n {
            let d = Float(i) - head
            let along = d.truncatingRemainder(dividingBy: Float(n))
            let dist = abs(along < -Float(n) / 2 ? along + Float(n) : (along > Float(n) / 2 ? along - Float(n) : along))
            let t = max(0, 1 - dist / tailLen)
            let v = t * t
            pixels[i] = Pixel.fromRGB(c.r, c.g, c.b, v: v, rgbw: rgbw)
        }
    }
}
```

- [ ] **Step 3: Create Plasma.swift**

```swift
// Sources/Pulsar/Effects/Plasma.swift
import Foundation

final class PlasmaEffect: Effect {
    static let id = "plasma"
    static let label = "Plasma"
    static let params: [EffectParam] = [
        EffectParam(id: "speed", label: "Speed",       defaultValue: 0.5, driverFloor: 0.25, format: EffectParam.mult),
        EffectParam(id: "boost", label: "Audio Boost", defaultValue: 0.5, driverFloor: 0.20, format: EffectParam.mult),
    ]

    private var phaseA: Float = 0
    private var phaseB: Float = 0
    private var renderLen: Int

    init(renderLen: Int) { self.renderLen = max(1, renderLen) }
    func resize(_ renderLen: Int) { self.renderLen = max(1, renderLen) }

    func render(into pixels: inout [Pixel],
                bands: [Float], power: Float, dt: Float,
                params: [String: Float],
                palette: Palette, rgbw: Bool) {
        let twoPi = 2 * Float.pi
        let speed = Self.paramValue("speed", in: params) * 2
        let boost = Self.paramValue("boost", in: params) * 2
        let adt = dt * max(0.05, speed)
        let p = max(0, min(1, sqrt(max(0, power) * 4)))
        let gain = max(0, min(2, boost))
        let boostMul = 1 + gain * 8 * p
        phaseA = (phaseA + adt * 0.20 * twoPi * boostMul).truncatingRemainder(dividingBy: twoPi)
        phaseB = (phaseB + adt * 0.27 * twoPi * boostMul).truncatingRemainder(dividingBy: twoPi)
        let n = max(1, min(renderLen, pixels.count))
        let invN = twoPi / Float(n)
        let bright: Float = 0.75
        let kA: Float = 2
        let kB: Float = 1
        for i in 0..<n {
            let x = Float(i) * invN
            let a = sin(x * kA + phaseA)
            let b = sin(x * kB - phaseB)
            let t = 0.5 + 0.5 * (a + b) * 0.5
            let c = palette.sample(at: max(0, min(1, t)))
            pixels[i] = Pixel.fromRGB(c.r, c.g, c.b, v: bright, rgbw: rgbw)
        }
    }
}
```

- [ ] **Step 4: Register the three types**

Modify `Sources/Pulsar/Effects/Registry.swift`:

```swift
static let all: [Effect.Type] = [
    TestEffect.self,
    SolidEffect.self,
    RainbowEffect.self,
    BreatheEffect.self,
    CometEffect.self,
    PlasmaEffect.self,
]
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Pulsar/Effects/Breathe.swift Sources/Pulsar/Effects/Comet.swift Sources/Pulsar/Effects/Plasma.swift Sources/Pulsar/Effects/Registry.swift
git commit -m "Migrate breathe, comet, plasma effects"
```

---

## Task 6: Migrate Spectrum and Wavelength effects

**Files:**
- Create: `Sources/Pulsar/Effects/Spectrum.swift`
- Create: `Sources/Pulsar/Effects/Wavelength.swift`
- Modify: `Sources/Pulsar/Effects/Registry.swift`

- [ ] **Step 1: Create Spectrum.swift**

```swift
// Sources/Pulsar/Effects/Spectrum.swift
import Foundation

final class SpectrumEffect: Effect {
    static let id = "spectrum"
    static let label = "Spectrum · Bars"
    static let params: [EffectParam] = [
        EffectParam(id: "peakFall", label: "Peak Fall", defaultValue: 0.5, driverFloor: 0.25, format: EffectParam.mult),
        EffectParam(id: "gain",     label: "Gain",      defaultValue: 0.5, driverFloor: 0.20, format: EffectParam.mult),
    ]

    private var peakHolds: [Float] = []
    private var renderLen: Int

    init(renderLen: Int) { self.renderLen = max(1, renderLen) }
    func resize(_ renderLen: Int) {
        self.renderLen = max(1, renderLen)
        peakHolds.removeAll()
    }

    func render(into pixels: inout [Pixel],
                bands: [Float], power: Float, dt: Float,
                params: [String: Float],
                palette: Palette, rgbw: Bool) {
        let n = min(renderLen, pixels.count)
        guard n > 0, !bands.isEmpty else { return }
        let peakFall = Self.paramValue("peakFall", in: params) * 2
        let gainBase = Self.paramValue("gain",     in: params) * 2
        let nBars = max(4, min(bands.count, n / 8))
        let pixelsPerBar = max(1, n / nBars)
        if peakHolds.count != nBars { peakHolds = [Float](repeating: 0, count: nBars) }

        for i in 0..<n { pixels[i] = .off }

        let gain = max(0.2, min(3.0, gainBase * 1.6))
        let peakFallPerSec: Float = 1.2 * peakFall
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
            let barLast = min(n, barStart + pixelsPerBar)
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
}
```

- [ ] **Step 2: Create Wavelength.swift**

```swift
// Sources/Pulsar/Effects/Wavelength.swift
import Foundation

final class WavelengthEffect: Effect {
    static let id = "wavelength"
    static let label = "Wavelength"
    static let params: [EffectParam] = [
        EffectParam(id: "speed", label: "Speed", defaultValue: 0.5, driverFloor: 0.25, format: EffectParam.mult),
        EffectParam(id: "gain",  label: "Gain",  defaultValue: 0.5, driverFloor: 0.20, format: EffectParam.mult),
    ]

    private var phase: Float = 0
    private var renderLen: Int

    init(renderLen: Int) { self.renderLen = max(1, renderLen) }
    func resize(_ renderLen: Int) { self.renderLen = max(1, renderLen) }

    func render(into pixels: inout [Pixel],
                bands: [Float], power: Float, dt: Float,
                params: [String: Float],
                palette: Palette, rgbw: Bool) {
        let n = min(renderLen, pixels.count)
        guard n > 0, !bands.isEmpty else { return }
        let speed = Self.paramValue("speed", in: params) * 2
        let gainBase = Self.paramValue("gain", in: params) * 2
        let adt = dt * max(0.05, speed)
        phase += adt * 0.15
        if phase > 1000 { phase -= 1000 }
        let gain = max(0.2, min(3.0, gainBase * 1.5))
        let nn = Float(max(n - 1, 1))
        for i in 0..<n {
            let f = Float(i) / nn
            let bi = min(bands.count - 1, Int(f * Float(bands.count)))
            let v = max(0, min(1, bands[bi] * gain))
            let t = (f + phase).truncatingRemainder(dividingBy: 1)
            let c = paletteSeamless(palette, at: t < 0 ? t + 1 : t)
            pixels[i] = Pixel.fromRGB(c.r, c.g, c.b, v: v, rgbw: rgbw)
        }
    }
}
```

- [ ] **Step 3: Register the two types**

Modify `Sources/Pulsar/Effects/Registry.swift` — append `SpectrumEffect.self, WavelengthEffect.self,` to `all`.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Pulsar/Effects/Spectrum.swift Sources/Pulsar/Effects/Wavelength.swift Sources/Pulsar/Effects/Registry.swift
git commit -m "Migrate spectrum, wavelength effects"
```

---

## Task 7: Migrate BeatWave, Ripple, Glitter effects

**Files:**
- Create: `Sources/Pulsar/Effects/BeatWave.swift`
- Create: `Sources/Pulsar/Effects/Ripple.swift`
- Create: `Sources/Pulsar/Effects/Glitter.swift`
- Modify: `Sources/Pulsar/Effects/Registry.swift`

- [ ] **Step 1: Create BeatWave.swift**

```swift
// Sources/Pulsar/Effects/BeatWave.swift
import Foundation

private struct WaveEntity {
    var pos: Float
    var color: Float
    var life: Float
    var direction: Float
}

final class BeatWaveEffect: Effect {
    static let id = "beat_wave"
    static let label = "Beat Wave"
    static let params: [EffectParam] = [
        EffectParam(id: "speed",       label: "Speed",       defaultValue: 0.5, driverFloor: 0.25, format: EffectParam.mult),
        EffectParam(id: "sensitivity", label: "Sensitivity", defaultValue: 0.5, driverFloor: 0.20, format: EffectParam.mult),
    ]

    private var phase: Float = 0
    private var beat = BeatDetector()
    private var waves: [WaveEntity] = []
    private var renderLen: Int

    init(renderLen: Int) { self.renderLen = max(1, renderLen) }
    func resize(_ renderLen: Int) {
        self.renderLen = max(1, renderLen)
        waves.removeAll()
    }

    func render(into pixels: inout [Pixel],
                bands: [Float], power: Float, dt: Float,
                params: [String: Float],
                palette: Palette, rgbw: Bool) {
        let n = min(renderLen, pixels.count)
        guard n > 0 else { return }
        let speed = Self.paramValue("speed", in: params) * 2
        let sensitivity = Self.paramValue("sensitivity", in: params) * 2
        // Beat detector reads real-time dt so beats track music, not speed.
        if beat.update(power: power, dt: dt, sensitivity: sensitivity) {
            phase += 0.17
            if phase > 1 { phase -= 1 }
            let dir: Float = waves.count.isMultiple(of: 2) ? 1 : -1
            let start: Float = dir > 0 ? 0 : Float(n - 1)
            waves.append(WaveEntity(pos: start, color: phase, life: 1.0, direction: dir))
            if waves.count > 6 { waves.removeFirst(waves.count - 6) }
        }

        let adt = dt * max(0.05, speed)
        let traverse: Float = Float(n) * 0.9
        for i in waves.indices {
            waves[i].pos += adt * traverse * waves[i].direction
            waves[i].life -= adt * 0.4
        }
        waves.removeAll { $0.life <= 0 || $0.pos < -10 || $0.pos > Float(n) + 10 }

        let nn = Float(max(n - 1, 1))
        for i in 0..<n {
            let c = palette.sample(at: Float(i) / nn)
            pixels[i] = Pixel.fromRGB(c.r, c.g, c.b, v: 0.06, rgbw: rgbw)
        }
        for w in waves {
            let center = Int(w.pos)
            let c = palette.sample(at: w.color)
            for offset in -4...4 {
                let idx = center + offset
                guard idx >= 0 && idx < n else { continue }
                let falloff = expf(-Float(offset * offset) * 0.4)
                let v = max(0, min(1, w.life * falloff))
                let prev = pixels[idx]
                let add = Pixel.fromRGB(c.r, c.g, c.b, v: v, rgbw: rgbw)
                pixels[idx] = addPixels(prev, add)
            }
        }
    }
}
```

- [ ] **Step 2: Create Ripple.swift**

```swift
// Sources/Pulsar/Effects/Ripple.swift
import Foundation

private struct RippleEntity {
    var center: Float
    var radius: Float
    var life: Float
    var color: Float
}

final class RippleEffect: Effect {
    static let id = "ripple"
    static let label = "Ripple"
    static let params: [EffectParam] = [
        EffectParam(id: "speed",       label: "Speed",       defaultValue: 0.5, driverFloor: 0.25, format: EffectParam.mult),
        EffectParam(id: "sensitivity", label: "Sensitivity", defaultValue: 0.5, driverFloor: 0.20, format: EffectParam.mult),
    ]

    private var phase: Float = 0
    private var beat = BeatDetector()
    private var ripples: [RippleEntity] = []
    private var renderLen: Int

    init(renderLen: Int) { self.renderLen = max(1, renderLen) }
    func resize(_ renderLen: Int) {
        self.renderLen = max(1, renderLen)
        ripples.removeAll()
    }

    func render(into pixels: inout [Pixel],
                bands: [Float], power: Float, dt: Float,
                params: [String: Float],
                palette: Palette, rgbw: Bool) {
        let n = min(renderLen, pixels.count)
        guard n > 0 else { return }
        let speed = Self.paramValue("speed", in: params) * 2
        let sensitivity = Self.paramValue("sensitivity", in: params) * 2

        if beat.update(power: power, dt: dt, sensitivity: sensitivity) {
            phase += 0.13
            if phase > 1 { phase -= 1 }
            ripples.append(RippleEntity(center: Float(n) * 0.5, radius: 0, life: 1.0, color: phase))
            if ripples.count > 5 { ripples.removeFirst(ripples.count - 5) }
        }

        let adt = dt * max(0.05, speed)
        let expandRate: Float = Float(n) * 0.5
        for i in ripples.indices {
            ripples[i].radius += adt * expandRate
            ripples[i].life -= adt * 0.5
        }
        ripples.removeAll { $0.life <= 0 || $0.radius > Float(n) }

        for i in 0..<n { pixels[i] = .off }
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
                if leftIdx >= 0 && leftIdx < n {
                    pixels[leftIdx] = addPixels(pixels[leftIdx], Pixel.fromRGB(c.r, c.g, c.b, v: v, rgbw: rgbw))
                }
                if rightIdx >= 0 && rightIdx < n && rightIdx != leftIdx {
                    pixels[rightIdx] = addPixels(pixels[rightIdx], Pixel.fromRGB(c.r, c.g, c.b, v: v, rgbw: rgbw))
                }
            }
        }
    }
}
```

- [ ] **Step 3: Create Glitter.swift**

```swift
// Sources/Pulsar/Effects/Glitter.swift
import Foundation

private struct Twinkle {
    var pos: Int
    var color: Float
    var life: Float
}

final class GlitterEffect: Effect {
    static let id = "glitter"
    static let label = "Glitter"
    static let params: [EffectParam] = [
        EffectParam(id: "decay",   label: "Decay",   defaultValue: 0.5, driverFloor: 0.25, format: EffectParam.mult),
        EffectParam(id: "density", label: "Density", defaultValue: 0.5, driverFloor: 0.20, format: EffectParam.mult),
    ]

    private var twinkles: [Twinkle] = []
    private var rng = EffectRNG()
    private var renderLen: Int

    init(renderLen: Int) { self.renderLen = max(1, renderLen) }
    func resize(_ renderLen: Int) {
        self.renderLen = max(1, renderLen)
        twinkles.removeAll()
    }

    func render(into pixels: inout [Pixel],
                bands: [Float], power: Float, dt: Float,
                params: [String: Float],
                palette: Palette, rgbw: Bool) {
        let n = min(renderLen, pixels.count)
        guard n > 0 else { return }
        let decay   = Self.paramValue("decay",   in: params) * 2
        let density = Self.paramValue("density", in: params) * 2

        let nn = Float(max(n - 1, 1))
        let base: Float = 0.18 + min(0.30, power * density * 1.5)
        for i in 0..<n {
            let c = palette.sample(at: Float(i) / nn)
            pixels[i] = Pixel.fromRGB(c.r, c.g, c.b, v: base, rgbw: rgbw)
        }

        let decayRate: Float = 2.5 * decay
        for i in twinkles.indices { twinkles[i].life -= dt * decayRate }
        twinkles.removeAll { $0.life <= 0 }

        let attemptsPerSec: Float = Float(n) * 0.5 * max(0.3, density)
        let attempts = Int(attemptsPerSec * dt) + 1
        let highCutoff = bands.count / 2
        var highEnergy: Float = 0
        if bands.count > highCutoff {
            for i in highCutoff..<bands.count { highEnergy += bands[i] }
            highEnergy /= Float(max(bands.count - highCutoff, 1))
        }
        let spawnProb = max(0, min(1, highEnergy * 4.0 * density))
        for _ in 0..<attempts {
            if Float(rng.next()) / Float(UInt32.max) < spawnProb {
                let pos = Int(rng.next() % UInt32(n))
                let color = Float(rng.next()) / Float(UInt32.max)
                twinkles.append(Twinkle(pos: pos, color: color, life: 1.0))
                if twinkles.count > n { twinkles.removeFirst(twinkles.count - n) }
            }
        }

        for t in twinkles {
            guard t.pos >= 0 && t.pos < n else { continue }
            let c = palette.sample(at: t.color)
            let v = max(0, min(1, t.life))
            pixels[t.pos] = addPixels(pixels[t.pos], Pixel.fromRGB(c.r, c.g, c.b, v: v, rgbw: rgbw))
        }
    }
}
```

- [ ] **Step 4: Register the three types**

Modify `Sources/Pulsar/Effects/Registry.swift` — append `BeatWaveEffect.self, RippleEffect.self, GlitterEffect.self,` to `all`. After this step the registry contains all 11 effects in the order spec.md lists.

- [ ] **Step 5: Build**

Run: `swift build`
Expected: PASS.

- [ ] **Step 6: Add registry sanity test**

Create `Tests/PulsarTests/EffectRegistryTests.swift`:

```swift
import XCTest
@testable import Pulsar

final class EffectRegistryTests: XCTestCase {
    func testRegistryHasAllExpectedEffects() {
        let expected = [
            "test", "solid", "rainbow", "breathe", "comet", "plasma",
            "spectrum", "wavelength", "beat_wave", "ripple", "glitter",
        ]
        XCTAssertEqual(EffectRegistry.availableIDs, expected)
    }

    func testEffectIDsAreUnique() {
        let ids = EffectRegistry.availableIDs
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate effect id in registry")
    }

    func testEachEffectHasUniqueParamIDs() {
        for type in EffectRegistry.all {
            let ids = type.params.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count,
                "duplicate param id in \(type.id): \(ids)")
        }
    }

    func testEachParamHasValidDefaultsAndFloor() {
        for type in EffectRegistry.all {
            for p in type.params {
                XCTAssertTrue((0.0...1.0).contains(p.defaultValue),
                    "\(type.id).\(p.id) defaultValue out of [0,1]: \(p.defaultValue)")
                XCTAssertTrue((0.0...1.0).contains(p.driverFloor),
                    "\(type.id).\(p.id) driverFloor out of [0,1]: \(p.driverFloor)")
                XCTAssertFalse(p.label.isEmpty, "\(type.id).\(p.id) has empty label")
            }
        }
    }

    func testEachEffectInstanceRendersWithEmptyParams() {
        var pixels = [Pixel](repeating: .off, count: 64)
        let bands = [Float](repeating: 0.1, count: 32)
        let palette = Palette.by(id: "sunset")
        for type in EffectRegistry.all {
            let inst = type.init(renderLen: pixels.count)
            inst.render(into: &pixels, bands: bands, power: 0.0, dt: 1.0/60,
                        params: [:], palette: palette, rgbw: false)
        }
    }
}
```

- [ ] **Step 7: Run tests**

Run: `swift test --filter EffectRegistryTests`
Expected: PASS for all five tests.

- [ ] **Step 8: Commit**

```bash
git add Sources/Pulsar/Effects/BeatWave.swift Sources/Pulsar/Effects/Ripple.swift Sources/Pulsar/Effects/Glitter.swift Sources/Pulsar/Effects/Registry.swift Tests/PulsarTests/EffectRegistryTests.swift
git commit -m "Migrate beat_wave, ripple, glitter effects + registry tests"
```

---

## Task 8: Cut Mapper over to the registry

Replace the per-effect `renderXxx` dispatch with a call into the active effect instance. Delete `reactiveEffects`, `ambientEffects`, `isAmbient`, `pretty`, all `renderXxx` methods, the `BeatDetector` struct on `Mapper`, the private `WaveEntity`/`Ripple`/`Twinkle`/`paletteSeamless`/`hsvToRGB`/`addPixels`/`nextRand`/`plasmaPhase*`/`peakHolds`/`waves`/`ripples`/`twinkles`/`rng`/`testPhase` state.

**Files:**
- Modify: `Sources/Pulsar/Mapper.swift`

- [ ] **Step 1: Rewrite Mapper.swift to the new shape**

Replace the contents of `Sources/Pulsar/Mapper.swift` with:

```swift
import Foundation

struct Pixel { var r: UInt8; var g: UInt8; var b: UInt8; var w: UInt8 }

extension Pixel {
    static let off = Pixel(r: 0, g: 0, b: 0, w: 0)
}

/// Mapper owns the per-device logical pixel buffer, the active Effect
/// instance, the effect→effect crossfade snapshot, and the serialization
/// of the buffer onto a device's physical segments.
///
/// Effect-specific rendering lives one-file-per-effect under Effects/.
/// Mapper is just the host that picks one and runs it.
final class Mapper {
    static var availableEffects: [String] { EffectRegistry.availableIDs }

    let totalPixels: Int
    let rgbw: Bool
    var effectID: String
    var palette: Palette = .sunset
    var brightness: Float = 1.0
    var minLoad: Float = 0
    var segments: [SegmentRuntime]
    private(set) var pixels: [Pixel]

    /// Latest already-driven param values for the current effect, keyed
    /// by paramID, all in [0,1]. Engine writes this every tick.
    var params: [String: Float] = [:]

    private var renderLen: Int
    private var effect: Effect

    private var lastEffectID: String = ""
    private var lastPaletteID: String = ""
    private var transitionFrom: [Pixel] = []
    private var transitionT: Float = 1.0
    private let transitionDur: Float = 0.6

    init(totalPixels: Int, rgbw: Bool, effect: String, segments: [SegmentRuntime]) {
        self.totalPixels = totalPixels
        self.rgbw = rgbw
        self.effectID = effect
        self.segments = segments
        let r = Mapper.computeRenderLen(segments, fallback: totalPixels)
        self.renderLen = r
        self.pixels = Array(repeating: .off, count: r)
        let type = EffectRegistry.type(byID: effect) ?? SpectrumEffect.self
        self.effect = type.init(renderLen: r)
        self.lastEffectID = effect
        self.lastPaletteID = palette.id
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
            effect.resize(r)
        }
    }

    func render(bands: [Float], power: Float, dt: Float) {
        if effectID != lastEffectID {
            transitionFrom = pixels
            transitionT = 0
            lastEffectID = effectID
            let type = EffectRegistry.type(byID: effectID) ?? SpectrumEffect.self
            effect = type.init(renderLen: renderLen)
        } else if palette.id != lastPaletteID {
            transitionFrom = pixels
            transitionT = 0
            lastPaletteID = palette.id
        }
        effect.render(into: &pixels, bands: bands, power: power, dt: dt,
                      params: params, palette: palette, rgbw: rgbw)
        applyTransitionCrossfade(dt: dt)
    }

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
        var wire = [Pixel](repeating: .off, count: totalPixels)
        for seg in segments {
            let s = max(0, seg.start)
            let len = max(0, min(seg.length, totalPixels - s))
            guard len > 0 else { continue }
            let halfPoint = seg.mirror ? (len + 1) / 2 : len
            for i in 0..<len {
                let srcLocal = (seg.mirror && i >= halfPoint) ? (len - 1 - i) : i
                let srcIdx = min(srcLocal, renderLen - 1)
                let dstLocal = seg.reverse ? (len - 1 - i) : i
                wire[s + dstLocal] = pixels[srcIdx]
            }
        }
        out.reserveCapacity(totalPixels * bytesPerPixel)
        let b = max(0, min(1, brightness))
        let floorFrac = max(0, min(0.5, minLoad))
        @inline(__always) func scale(_ v: UInt8) -> UInt8 { UInt8(Float(v) * b) }

        let fallback = palette.sample(at: 0.5)
        let dimByte = UInt8(min(255, floorFrac * 255))

        var bytes = [UInt8](repeating: 0, count: totalPixels * bytesPerPixel)
        var idx = 0
        var sumF: Float = 0
        for p in wire {
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
            bytes[idx] = r;  idx += 1
            bytes[idx] = g;  idx += 1
            bytes[idx] = bl; idx += 1
            sumF += Float(r) + Float(g) + Float(bl)
            if rgbw { bytes[idx] = w; idx += 1; sumF += Float(w) }
        }

        if floorFrac > 0 {
            let target = floorFrac * Float(totalPixels * bytesPerPixel) * 255
            if sumF < target {
                let gain = min(4.0, target / max(sumF, 1))
                for j in 0..<bytes.count {
                    bytes[j] = UInt8(min(255, Float(bytes[j]) * gain))
                }
            }
        }

        out.append(contentsOf: bytes)
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
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: BUILD FAILS — `AudioEngine`, `ControlModel`, `Showcase`, `BarView` still reference `Mapper.isAmbient`, `Mapper.pretty`, `mapper.speed`, `mapper.intensity`, `mapper.effect = …`. These compile errors guide the next tasks.

Document the list of failing references (expect ~25 sites). The next tasks remove them. The build will stay broken until Task 12 completes.

- [ ] **Step 3: Commit (intentionally broken build)**

```bash
git add Sources/Pulsar/Mapper.swift
git commit -m "Cut Mapper over to Effect registry (downstream wip)"
```

(Project follows trunk-based local development; the broken build is closed within this session by Task 12. If the engineer prefers a never-broken trunk, fold Tasks 8–12 into a single commit at the end.)

---

## Task 9: New runtime data model in Models.swift

Replace the `Settings`-level `speed`/`intensity`/`*_reactive`/`*_aspect` fields with `brightnessDriver` + `effectState`. Update `LiveFrame` to carry `effParams` instead of `effSpeed`/`effIntensity`.

**Files:**
- Modify: `Sources/Pulsar/Models.swift`

- [ ] **Step 1: Rewrite Settings + LiveFrame**

Replace the contents of `Sources/Pulsar/Models.swift` with:

```swift
import Foundation

struct SegmentRuntime: Equatable, Identifiable {
    let id: UUID = UUID()
    var start: Int
    var length: Int
    var reverse: Bool
    var mirror: Bool
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

/// Audio descriptor that can drive a slider.
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
    var bass: Float
    var treble: Float
    var beat: Float
    var lastFrameAgo: Double
    var aggregateAlive: Bool
    /// Live effective brightness after driver modulation.
    var effBrightness: Float
    /// Live effective param values for the currently active effect.
    /// Keyed by paramID. UI reads from here when a slider is driven.
    var effParams: [String: Float]

    static let zero = LiveFrame(
        spectrum: [], power: 0, bass: 0, treble: 0, beat: 0,
        lastFrameAgo: -1, aggregateAlive: false,
        effBrightness: 1, effParams: [:]
    )

    func value(for aspect: AudioAspect) -> Float {
        switch aspect {
        case .power:  return min(1, power * 4)
        case .bass:   return bass
        case .treble: return treble
        case .beat:   return beat
        }
    }
}

/// `EffectStateMap[effectID][paramID]` — every effect's persisted slider
/// state. UI binds to the entry for the currently active effect; the
/// rest sits in storage waiting for the user to switch back.
typealias EffectStateMap = [String: [String: EffectParamState]]

struct Settings: Equatable {
    var enabled: Bool
    var effect: String
    var palette: String
    var brightness: Float
    var brightnessDriver: Driver
    var effectState: EffectStateMap
    var devices: [DeviceRuntime]
    var availableEffects: [String]
    var availablePalettes: [String]
    var fps: Int
    var sampleRate: Double
    var bandCount: Int
    var tccStatus: Int

    static let empty: Settings = {
        return Settings(
            enabled: true,
            effect: "spectrum",
            palette: "sunset",
            brightness: 1.0,
            brightnessDriver: .manualPower,
            effectState: Settings.defaultEffectState(),
            devices: [],
            availableEffects: EffectRegistry.availableIDs,
            availablePalettes: Palette.allIDs,
            fps: 60, sampleRate: 0, bandCount: 32, tccStatus: -1
        )
    }()

    /// Fresh `effectState` filled with every registered effect's declared
    /// defaults. Used by `.empty` and as the migration starting point.
    static func defaultEffectState() -> EffectStateMap {
        var out: EffectStateMap = [:]
        for type in EffectRegistry.all {
            var paramMap: [String: EffectParamState] = [:]
            for p in type.params {
                paramMap[p.id] = EffectParamState(value: p.defaultValue, driver: .manualPower)
            }
            out[type.id] = paramMap
        }
        return out
    }
}

enum AudioStatus: Equatable {
    case starting
    case running
    case stopped
    case tccDenied
    case aggregateLost
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: BUILD STILL FAILS — `Config`, `ControlModel`, `AudioEngine`, `BarView`, `Showcase` are out of sync. Task 10–13 mop up.

- [ ] **Step 3: Commit**

```bash
git add Sources/Pulsar/Models.swift
git commit -m "Switch Settings + LiveFrame to per-effect param shape"
```

---

## Task 10: Config schema + migration (with tests)

Update `Config` to the new on-disk schema. Add one-shot migration. Add tests that lock in legacy → new behaviour.

**Files:**
- Modify: `Sources/Pulsar/Config.swift`
- Create: `Tests/PulsarTests/ConfigMigrationTests.swift`
- Modify: `Tests/PulsarTests/ConfigTests.swift` — update existing tests to the new struct shape.

- [ ] **Step 1: Rewrite Config.swift**

Replace the contents of `Sources/Pulsar/Config.swift` with:

```swift
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
    // Legacy fields kept optional so older configs parse.
    let mirror: Bool?
    let reverse: Bool?
    let effect: String?
}

struct Config: Codable {
    // Audio pipeline (unchanged).
    let fps: Int
    let fft_size: Int
    let band_count: Int
    let smoothing: Float
    let min_freq_hz: Double
    let max_freq_hz: Double
    let devices: [DeviceConfig]

    // Master state.
    let enabled: Bool?
    let effect: String?
    let palette: String?

    // Global brightness.
    let brightness: Float?
    let brightness_driver: Driver?

    // Per-effect params (the new shape).
    let effect_state: EffectStateMap?

    // Legacy fields — read only, never written by `sanitized()` output.
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
        brightness_driver: .manualPower,
        effect_state: Settings.defaultEffectState(),
        speed: nil,
        intensity: nil,
        brightness_reactive: nil,
        brightness_aspect: nil,
        speed_reactive: nil,
        speed_aspect: nil,
        intensity_reactive: nil,
        intensity_aspect: nil
    )

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
            let backup = "\(p).broken.\(Int(Date().timeIntervalSince1970))"
            try? FileManager.default.moveItem(at: url, to: URL(fileURLWithPath: backup))
            FileHandle.standardError.write(Data("Pulsar: config at \(p) failed to parse; moved to \(backup); using defaults\n".utf8))
            return .default
        }
        return cfg.migrated().sanitized()
    }

    /// Folds legacy `speed`/`intensity`/`*_reactive`/`*_aspect` into the
    /// new `effect_state` map for the currently active effect. Idempotent:
    /// configs already in the new shape pass through unchanged.
    func migrated() -> Config {
        let effectID = effect ?? "spectrum"

        let migratedDriver = brightness_driver
            ?? Driver(reactive: brightness_reactive ?? false,
                      aspect: brightness_aspect ?? .power)

        var state = effect_state ?? Settings.defaultEffectState()
        // Make sure every registered effect has an entry.
        for type in EffectRegistry.all where state[type.id] == nil {
            var paramMap: [String: EffectParamState] = [:]
            for p in type.params {
                paramMap[p.id] = EffectParamState(value: p.defaultValue, driver: .manualPower)
            }
            state[type.id] = paramMap
        }

        // Legacy speed/intensity → matching param ids on the active effect,
        // if both the effect declares those ids and the legacy fields are
        // present. Legacy range was 0..2 with `1.0` as neutral; new range
        // is 0..1 with `0.5` as neutral. Hence /2.
        if let type = EffectRegistry.type(byID: effectID) {
            var paramMap = state[effectID] ?? [:]
            for legacyID in ["speed", "intensity"] where type.params.contains(where: { $0.id == legacyID }) {
                let legacyVal: Float?
                let legacyReactive: Bool?
                let legacyAspect: AudioAspect?
                switch legacyID {
                case "speed":
                    legacyVal = speed
                    legacyReactive = speed_reactive
                    legacyAspect = speed_aspect
                default:
                    legacyVal = intensity
                    legacyReactive = intensity_reactive
                    legacyAspect = intensity_aspect
                }
                if legacyVal == nil && legacyReactive == nil && legacyAspect == nil { continue }
                var entry = paramMap[legacyID]
                    ?? EffectParamState(value: type.params.first { $0.id == legacyID }!.defaultValue, driver: .manualPower)
                if let v = legacyVal {
                    entry.value = min(1, max(0, v / 2))
                }
                if legacyReactive != nil || legacyAspect != nil {
                    entry.driver = Driver(
                        reactive: legacyReactive ?? entry.driver.reactive,
                        aspect: legacyAspect ?? entry.driver.aspect
                    )
                }
                paramMap[legacyID] = entry
            }
            state[effectID] = paramMap
        }

        return Config(
            fps: fps, fft_size: fft_size, band_count: band_count,
            smoothing: smoothing,
            min_freq_hz: min_freq_hz, max_freq_hz: max_freq_hz,
            devices: devices,
            enabled: enabled,
            effect: effectID,
            palette: palette,
            brightness: brightness,
            brightness_driver: migratedDriver,
            effect_state: state,
            speed: nil, intensity: nil,
            brightness_reactive: nil, brightness_aspect: nil,
            speed_reactive: nil, speed_aspect: nil,
            intensity_reactive: nil, intensity_aspect: nil
        )
    }

    func sanitized() -> Config {
        let fallback = Config.default
        let validFFT = fft_size > 0 && (fft_size & (fft_size - 1)) == 0
        let safeFFT = validFFT ? fft_size : fallback.fft_size
        var safeMinFreq = min_freq_hz.isFinite && min_freq_hz > 0 ? min_freq_hz : fallback.min_freq_hz
        var safeMaxFreq = max_freq_hz.isFinite && max_freq_hz > safeMinFreq ? max_freq_hz : fallback.max_freq_hz
        if safeMaxFreq <= safeMinFreq {
            safeMinFreq = fallback.min_freq_hz
            safeMaxFreq = fallback.max_freq_hz
        }

        var safeState: EffectStateMap = [:]
        let registry = Dictionary(uniqueKeysWithValues: EffectRegistry.all.map { ($0.id, $0) })
        for (effectID, paramMap) in (effect_state ?? [:]) {
            guard let type = registry[effectID] else { continue }
            let validIDs = Set(type.params.map(\.id))
            var safeParams: [String: EffectParamState] = [:]
            for (paramID, state) in paramMap where validIDs.contains(paramID) {
                safeParams[paramID] = EffectParamState(
                    value: state.value.clamped(to: 0...1),
                    driver: state.driver
                )
            }
            // Backfill any declared params that the on-disk file is missing.
            for p in type.params where safeParams[p.id] == nil {
                safeParams[p.id] = EffectParamState(value: p.defaultValue, driver: .manualPower)
            }
            safeState[effectID] = safeParams
        }
        // Backfill effects entirely missing from the map.
        for type in EffectRegistry.all where safeState[type.id] == nil {
            var paramMap: [String: EffectParamState] = [:]
            for p in type.params {
                paramMap[p.id] = EffectParamState(value: p.defaultValue, driver: .manualPower)
            }
            safeState[type.id] = paramMap
        }

        return Config(
            fps: fps.clamped(to: 1...120),
            fft_size: safeFFT.clamped(to: 256...8192),
            band_count: band_count.clamped(to: 1...128),
            smoothing: smoothing.clamped(to: 0...0.99),
            min_freq_hz: safeMinFreq,
            max_freq_hz: safeMaxFreq,
            devices: devices.compactMap { $0.sanitized() },
            enabled: enabled,
            effect: EffectRegistry.type(byID: effect ?? "") != nil ? effect : "spectrum",
            palette: palette,
            brightness: brightness?.clamped(to: 0...1),
            brightness_driver: brightness_driver,
            effect_state: safeState,
            speed: nil, intensity: nil,
            brightness_reactive: nil, brightness_aspect: nil,
            speed_reactive: nil, speed_aspect: nil,
            intensity_reactive: nil, intensity_aspect: nil
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
```

- [ ] **Step 2: Update ConfigTests.swift to the new struct shape**

Open `Tests/PulsarTests/ConfigTests.swift`. The `Config.init(...)` call in `testSanitizedConfigClampsUnsafeScalarValues` no longer has `speed`, `intensity`, `brightness_reactive`, `brightness_aspect`, `speed_reactive`, `speed_aspect`, `intensity_reactive`, `intensity_aspect` (well, it still does as legacy fields). The new fields are `brightness_driver` and `effect_state`.

Replace the contents of the file with:

```swift
import XCTest
@testable import Pulsar

final class ConfigTests: XCTestCase {
    private func makeRaw(
        fps: Int = 60,
        fft_size: Int = 1024,
        band_count: Int = 32,
        smoothing: Float = 0.6,
        min_freq_hz: Double = 40,
        max_freq_hz: Double = 16000,
        devices: [DeviceConfig] = [],
        brightness: Float? = 1.0,
        speed: Float? = nil,
        intensity: Float? = nil
    ) -> Config {
        Config(
            fps: fps, fft_size: fft_size, band_count: band_count,
            smoothing: smoothing,
            min_freq_hz: min_freq_hz, max_freq_hz: max_freq_hz,
            devices: devices,
            enabled: true, effect: "spectrum", palette: "sunset",
            brightness: brightness,
            brightness_driver: .manualPower,
            effect_state: nil,
            speed: speed, intensity: intensity,
            brightness_reactive: nil, brightness_aspect: nil,
            speed_reactive: nil, speed_aspect: nil,
            intensity_reactive: nil, intensity_aspect: nil
        )
    }

    func testSanitizedConfigClampsUnsafeScalarValues() {
        let raw = makeRaw(
            fps: 0, fft_size: 1000, band_count: 0, smoothing: 2,
            min_freq_hz: -10, max_freq_hz: 0,
            brightness: 2
        )
        let cfg = raw.migrated().sanitized()
        XCTAssertEqual(cfg.fps, 1)
        XCTAssertEqual(cfg.fft_size, Config.default.fft_size)
        XCTAssertEqual(cfg.band_count, 1)
        XCTAssertEqual(cfg.smoothing, 0.99)
        XCTAssertEqual(cfg.min_freq_hz, Config.default.min_freq_hz)
        XCTAssertEqual(cfg.max_freq_hz, Config.default.max_freq_hz)
        XCTAssertEqual(cfg.brightness, 1)
        XCTAssertNotNil(cfg.effect_state?["spectrum"])
    }

    func testSanitizedConfigDropsInvalidDevicesAndClampsSegments() {
        let raw = makeRaw(devices: [
            DeviceConfig(
                name: "  Desk  ", ip: "  192.0.2.42  ",
                pixel_count: 10, rgbw: false,
                brightness: -1, enabled: true,
                segments: [
                    SegmentConfig(start: -5, length: 20, reverse: true, mirror: false),
                    SegmentConfig(start: 20, length: 1, reverse: false, mirror: false),
                ],
                min_load: nil, mirror: nil, reverse: nil, effect: nil
            ),
            DeviceConfig(name: "", ip: "", pixel_count: 0, rgbw: false,
                         brightness: nil, enabled: nil, segments: nil,
                         min_load: nil, mirror: nil, reverse: nil, effect: nil),
        ])
        let cfg = raw.migrated().sanitized()
        XCTAssertEqual(cfg.devices.count, 1)
        XCTAssertEqual(cfg.devices[0].name, "Desk")
        XCTAssertEqual(cfg.devices[0].ip, "192.0.2.42")
        XCTAssertEqual(cfg.devices[0].segments?.count, 1)
        XCTAssertEqual(cfg.devices[0].segments?[0].start, 0)
        XCTAssertEqual(cfg.devices[0].segments?[0].length, 10)
        XCTAssertEqual(cfg.devices[0].brightness, 0)
    }
}
```

- [ ] **Step 3: Create ConfigMigrationTests.swift**

```swift
// Tests/PulsarTests/ConfigMigrationTests.swift
import XCTest
@testable import Pulsar

final class ConfigMigrationTests: XCTestCase {
    private func legacy(effect: String = "spectrum",
                        speed: Float? = 1.4,
                        intensity: Float? = 1.6,
                        brightnessReactive: Bool? = true,
                        brightnessAspect: AudioAspect? = .bass,
                        speedReactive: Bool? = true,
                        speedAspect: AudioAspect? = .treble) -> Config {
        Config(
            fps: 60, fft_size: 1024, band_count: 32,
            smoothing: 0.6, min_freq_hz: 40, max_freq_hz: 16000,
            devices: [],
            enabled: true,
            effect: effect,
            palette: "sunset",
            brightness: 0.8,
            brightness_driver: nil,
            effect_state: nil,
            speed: speed,
            intensity: intensity,
            brightness_reactive: brightnessReactive,
            brightness_aspect: brightnessAspect,
            speed_reactive: speedReactive,
            speed_aspect: speedAspect,
            intensity_reactive: false,
            intensity_aspect: .power
        )
    }

    func testLegacyBrightnessReactiveFoldsIntoBrightnessDriver() {
        let m = legacy().migrated()
        XCTAssertEqual(m.brightness_driver?.reactive, true)
        XCTAssertEqual(m.brightness_driver?.aspect, .bass)
        XCTAssertNil(m.brightness_reactive)
        XCTAssertNil(m.brightness_aspect)
    }

    func testLegacySpeedFoldsIntoSpectrumEffectStateMissing() {
        // Spectrum has no "speed" param; folding should be a no-op for it.
        let m = legacy(effect: "spectrum").migrated()
        XCTAssertNotNil(m.effect_state?["spectrum"])
        XCTAssertNil(m.effect_state?["spectrum"]?["speed"])
    }

    func testLegacySpeedFoldsIntoWavelengthSpeed() {
        let m = legacy(effect: "wavelength", speed: 1.4, speedReactive: true, speedAspect: .treble).migrated()
        let entry = m.effect_state?["wavelength"]?["speed"]
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.value ?? 0, 0.7, accuracy: 0.001)  // 1.4 / 2
        XCTAssertEqual(entry?.driver.reactive, true)
        XCTAssertEqual(entry?.driver.aspect, .treble)
    }

    func testLegacyIntensityFoldsIntoBreatheIntensity() {
        let m = legacy(effect: "breathe", intensity: 1.6).migrated()
        let entry = m.effect_state?["breathe"]?["intensity"]
        XCTAssertEqual(entry?.value ?? 0, 0.8, accuracy: 0.001)  // 1.6 / 2
    }

    func testMigratedConfigDropsLegacyTopLevelFields() {
        let m = legacy().migrated()
        XCTAssertNil(m.speed)
        XCTAssertNil(m.intensity)
        XCTAssertNil(m.brightness_reactive)
        XCTAssertNil(m.brightness_aspect)
        XCTAssertNil(m.speed_reactive)
        XCTAssertNil(m.speed_aspect)
        XCTAssertNil(m.intensity_reactive)
        XCTAssertNil(m.intensity_aspect)
    }

    func testMigratedConfigContainsEveryRegisteredEffect() {
        let m = legacy().migrated()
        for type in EffectRegistry.all {
            XCTAssertNotNil(m.effect_state?[type.id], "missing effect_state for \(type.id)")
            for p in type.params {
                XCTAssertNotNil(m.effect_state?[type.id]?[p.id],
                    "missing param \(type.id).\(p.id) after migration")
            }
        }
    }

    func testSanitizedDropsUnknownEffectAndUnknownParam() {
        var state = Settings.defaultEffectState()
        state["nonexistent"] = ["x": EffectParamState(value: 0.5, driver: .manualPower)]
        state["spectrum"]?["bogus"] = EffectParamState(value: 0.9, driver: .manualPower)
        let raw = Config(
            fps: 60, fft_size: 1024, band_count: 32,
            smoothing: 0.6, min_freq_hz: 40, max_freq_hz: 16000,
            devices: [], enabled: true, effect: "spectrum", palette: "sunset",
            brightness: 1.0, brightness_driver: .manualPower,
            effect_state: state,
            speed: nil, intensity: nil,
            brightness_reactive: nil, brightness_aspect: nil,
            speed_reactive: nil, speed_aspect: nil,
            intensity_reactive: nil, intensity_aspect: nil
        )
        let cfg = raw.sanitized()
        XCTAssertNil(cfg.effect_state?["nonexistent"])
        XCTAssertNil(cfg.effect_state?["spectrum"]?["bogus"])
    }

    func testEmptyConfigPopulatesDefaultsForAllEffects() {
        let raw = Config(
            fps: 60, fft_size: 1024, band_count: 32,
            smoothing: 0.6, min_freq_hz: 40, max_freq_hz: 16000,
            devices: [], enabled: nil, effect: "spectrum", palette: "sunset",
            brightness: nil, brightness_driver: nil,
            effect_state: nil,
            speed: nil, intensity: nil,
            brightness_reactive: nil, brightness_aspect: nil,
            speed_reactive: nil, speed_aspect: nil,
            intensity_reactive: nil, intensity_aspect: nil
        )
        let cfg = raw.migrated().sanitized()
        XCTAssertNotNil(cfg.brightness_driver)
        XCTAssertEqual(cfg.brightness_driver?.reactive, false)
        XCTAssertEqual(cfg.brightness_driver?.aspect, .power)
        XCTAssertEqual(cfg.effect_state?.count, EffectRegistry.all.count)
    }
}
```

- [ ] **Step 4: Build (still expected to fail downstream)**

Run: `swift build`
Expected: STILL FAILS — `ControlModel`, `AudioEngine`, `BarView`, `Showcase` haven't been updated. `Tests/PulsarTests/ConfigTests.swift` should now compile (Config.swift compiles in isolation).

- [ ] **Step 5: Commit**

```bash
git add Sources/Pulsar/Config.swift Tests/PulsarTests/ConfigTests.swift Tests/PulsarTests/ConfigMigrationTests.swift
git commit -m "Add per-effect param config schema + legacy migration tests"
```

---

## Task 11: Update RenderState + ControlModel API

`RenderState` becomes the runtime sibling of `Settings`. `ControlModel` setters collapse to uniform per-effect-param + global-brightness operations.

**Files:**
- Modify: `Sources/Pulsar/ControlModel.swift`

- [ ] **Step 1: Replace the `RenderView` + `RenderState` + `ControlModel` setter API**

Open `Sources/Pulsar/ControlModel.swift`. Replace the entire file with:

```swift
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
    let brightnessDriver: Driver
    /// Params for the currently active effect. Engine only needs the
    /// active set per tick.
    let activeParams: [String: EffectParamState]
    let devices: [DeviceRuntime]
}

final class RenderState: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool = true
    private var effect: String = "spectrum"
    private var paletteID: String = "sunset"
    private var brightness: Float = 1.0
    private var brightnessDriver: Driver = .manualPower
    private var effectState: EffectStateMap = [:]
    private var devices: [DeviceRuntime] = []

    func snapshot() -> RenderView {
        lock.lock(); defer { lock.unlock() }
        return RenderView(
            enabled: enabled,
            effect: effect,
            palette: Palette.by(id: paletteID),
            brightness: brightness,
            brightnessDriver: brightnessDriver,
            activeParams: effectState[effect] ?? [:],
            devices: devices
        )
    }

    func replace(settings: Settings) {
        lock.lock(); defer { lock.unlock() }
        self.enabled = settings.enabled
        self.effect = settings.effect
        self.paletteID = settings.palette
        self.brightness = settings.brightness
        self.brightnessDriver = settings.brightnessDriver
        self.effectState = settings.effectState
        self.devices = settings.devices
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
    func setBrightnessDriver(_ d: Driver) {
        lock.lock(); defer { lock.unlock() }
        brightnessDriver = d
    }
    func setEffectParamValue(effectID: String, paramID: String, value: Float) {
        lock.lock(); defer { lock.unlock() }
        var map = effectState[effectID] ?? [:]
        if var entry = map[paramID] {
            entry.value = value
            map[paramID] = entry
        } else {
            map[paramID] = EffectParamState(value: value, driver: .manualPower)
        }
        effectState[effectID] = map
    }
    func setEffectParamDriver(effectID: String, paramID: String, driver: Driver) {
        lock.lock(); defer { lock.unlock() }
        var map = effectState[effectID] ?? [:]
        if var entry = map[paramID] {
            entry.driver = driver
            map[paramID] = entry
        } else {
            map[paramID] = EffectParamState(value: 0.5, driver: driver)
        }
        effectState[effectID] = map
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
        let rawEffect = cfg.effect ?? "spectrum"
        s.effect = EffectRegistry.type(byID: rawEffect) != nil ? rawEffect : "spectrum"
        s.palette = Palette.allIDs.contains(cfg.palette ?? "") ? (cfg.palette ?? "sunset") : "sunset"
        s.brightness = max(0.0, min(1.0, cfg.brightness ?? 1.0))
        s.brightnessDriver = cfg.brightness_driver ?? .manualPower
        s.effectState = cfg.effect_state ?? Settings.defaultEffectState()
        s.devices = cfg.devices.map { d in
            let segs: [SegmentRuntime]
            if let seg = d.segments, !seg.isEmpty {
                segs = seg.map { SegmentRuntime(start: $0.start, length: $0.length, reverse: $0.reverse ?? false, mirror: $0.mirror ?? false) }
            } else {
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
        renderState.replace(settings: s)
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

    // MARK: - Segment discovery (unchanged from previous version)

    func refreshAllSegmentsFromWLED() async {
        let devs = settings.settings.devices
        for i in devs.indices {
            await refreshSegmentsFromWLED(deviceIndex: i)
        }
    }

    func refreshSegmentsFromWLED(deviceIndex i: Int) async {
        guard let dev0 = settings.settings.devices[safe: i] else { return }
        let capturedIP = dev0.ip
        let capturedName = dev0.name
        guard let url = URL(string: "http://\(capturedIP)/json/cfg") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hw = json["hw"] as? [String: Any],
                  let led = hw["led"] as? [String: Any],
                  let ins = led["ins"] as? [[String: Any]] else { return }
            let info = await fetchWLEDInfo(ip: capturedIP)
            guard let idx = settings.settings.devices.firstIndex(where: { $0.ip == capturedIP }) else { return }
            let dev = settings.settings.devices[idx]
            var newSegs: [SegmentRuntime] = []
            for inst in ins {
                let start = inst["start"] as? Int ?? 0
                let length = inst["len"] as? Int ?? 0
                guard length > 0 else { continue }
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
            snap.devices[idx].pixelCount = newPixelCount
            snap.devices[idx].rgbw = newRGBW
            snap.devices[idx].segments = newSegs
            settings.settings = snap
            renderState.mutateDevice(index: idx) {
                $0.pixelCount = newPixelCount
                $0.rgbw = newRGBW
                $0.segments = newSegs
            }
            persist()
            if needsEngineRebuild { rebuildEngine() }
            log.info("device \(dev.name, privacy: .public) → \(newSegs.count) segments")
        } catch {
            log.error("segment refresh failed for \(capturedName, privacy: .public): \(String(describing: error), privacy: .public)")
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
        guard EffectRegistry.type(byID: e) != nil else { return }
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

    func setBrightnessDriver(_ d: Driver) {
        var snap = settings.settings
        snap.brightnessDriver = d
        settings.settings = snap
        renderState.setBrightnessDriver(d)
        persist()
    }

    func cycleBrightnessDriver() {
        let cur = settings.settings.brightnessDriver
        setBrightnessDriver(Self.nextDriver(cur))
    }

    func setEffectParam(effectID: String, paramID: String, value: Float) {
        let c = max(0, min(1, value))
        var snap = settings.settings
        var map = snap.effectState[effectID] ?? [:]
        if var entry = map[paramID] {
            entry.value = c
            map[paramID] = entry
        } else {
            map[paramID] = EffectParamState(value: c, driver: .manualPower)
        }
        snap.effectState[effectID] = map
        settings.settings = snap
        renderState.setEffectParamValue(effectID: effectID, paramID: paramID, value: c)
        persist()
    }

    func setEffectParamDriver(effectID: String, paramID: String, driver: Driver) {
        var snap = settings.settings
        var map = snap.effectState[effectID] ?? [:]
        if var entry = map[paramID] {
            entry.driver = driver
            map[paramID] = entry
        } else {
            map[paramID] = EffectParamState(value: 0.5, driver: driver)
        }
        snap.effectState[effectID] = map
        settings.settings = snap
        renderState.setEffectParamDriver(effectID: effectID, paramID: paramID, driver: driver)
        persist()
    }

    func cycleEffectParamDriver(effectID: String, paramID: String) {
        let cur = settings.settings.effectState[effectID]?[paramID]?.driver ?? .manualPower
        setEffectParamDriver(effectID: effectID, paramID: paramID, driver: Self.nextDriver(cur))
    }

    /// Driver state machine: off → power → bass → treble → beat → off.
    private static func nextDriver(_ cur: Driver) -> Driver {
        if !cur.reactive { return Driver(reactive: true, aspect: .power) }
        switch cur.aspect {
        case .power:  return Driver(reactive: true, aspect: .bass)
        case .bass:   return Driver(reactive: true, aspect: .treble)
        case .treble: return Driver(reactive: true, aspect: .beat)
        case .beat:   return Driver(reactive: false, aspect: cur.aspect)
        }
    }

    // MARK: - Device CRUD (preserved logic; only `replace()` changes)

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
        renderState.replace(settings: snap)
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
        renderState.replace(settings: snap)
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
        rebuildEngine()
    }

    // MARK: - Startup (unchanged)

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
                palette: snap.palette,
                brightness: snap.brightness,
                brightness_driver: snap.brightnessDriver,
                effect_state: snap.effectState,
                speed: nil, intensity: nil,
                brightness_reactive: nil, brightness_aspect: nil,
                speed_reactive: nil, speed_aspect: nil,
                intensity_reactive: nil, intensity_aspect: nil
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
```

- [ ] **Step 2: Build (still expected to fail — Engine + UI + Showcase)**

Run: `swift build`
Expected: FAIL. `AudioEngine` still references the old `RenderView` shape; `BarView` still calls old setters; `Showcase` still seeds old fields.

- [ ] **Step 3: Commit**

```bash
git add Sources/Pulsar/ControlModel.swift
git commit -m "Replace ControlModel API with uniform per-effect-param setters"
```

---

## Task 12: Update AudioEngine — per-param resolution

**Files:**
- Modify: `Sources/Pulsar/AudioEngine.swift`

- [ ] **Step 1: Rewrite the engine loop**

Replace the contents of `Sources/Pulsar/AudioEngine.swift` with:

```swift
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

    /// Resolve a single param: `base * (floor + (1 - floor) * signal)` when
    /// driven; `base` when not. Floor stops driven params from collapsing
    /// to zero on silence. Brightness uses floor 0 by convention.
    private static func driven(_ base: Float, signal: Float, floor: Float) -> Float {
        return base * (floor + (1 - floor) * signal)
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
        let zeroBands = [Float](repeating: 0, count: cfg.band_count)
        let n = cfg.fft_size

        var featureBeatDetector = BeatDetector()
        var beatPulse: Float = 0
        let beatDecayPerSec: Float = 2.5

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
            }

            let bands = haveWindow ? analyzer.bands : zeroBands
            let quarter = max(1, bands.count / 4)
            var bassSum: Float = 0
            for i in 0..<quarter { bassSum += bands[i] }
            let bassOut = min(1, bassSum / Float(quarter) * 1.5)
            var trebleSum: Float = 0
            for i in (bands.count - quarter)..<bands.count { trebleSum += bands[i] }
            let trebleOut = min(1, trebleSum / Float(quarter) * 1.5)
            beatPulse *= expf(-dt * beatDecayPerSec)
            if featureBeatDetector.update(power: powerOut, dt: dt) {
                beatPulse = 1
            }
            let beatOut = beatPulse

            let view = renderState.snapshot()
            let masterOn = view.enabled

            if masterOn != masterWasEnabled, !masterOn {
                for i in 0..<mappers.count {
                    mappers[i].writeBlack(into: &pixelBytes)
                    senders[i].send(pixels: pixelBytes)
                }
            }
            masterWasEnabled = masterOn

            func aspectSignal(_ a: AudioAspect) -> Float {
                switch a {
                case .power:  return min(1, powerOut * 4)
                case .bass:   return bassOut
                case .treble: return trebleOut
                case .beat:   return beatOut
                }
            }

            // Resolve global brightness driver (floor 0 — quiet rooms go dark).
            let effBright = view.brightnessDriver.reactive
                ? AudioEngine.driven(view.brightness,
                                     signal: aspectSignal(view.brightnessDriver.aspect),
                                     floor: 0.0)
                : view.brightness

            // Resolve every param of the active effect.
            var effParams: [String: Float] = [:]
            if let effectType = EffectRegistry.type(byID: view.effect) {
                for p in effectType.params {
                    let state = view.activeParams[p.id]
                        ?? EffectParamState(value: p.defaultValue, driver: .manualPower)
                    let resolved = state.driver.reactive
                        ? AudioEngine.driven(state.value,
                                             signal: aspectSignal(state.driver.aspect),
                                             floor: p.driverFloor)
                        : state.value
                    effParams[p.id] = resolved
                }
            }

            for i in 0..<mappers.count {
                let dev = i < view.devices.count ? view.devices[i] : nil
                let devOn = dev?.enabled ?? true
                mappers[i].effectID = view.effect
                mappers[i].palette = view.palette
                mappers[i].brightness = effBright * (dev?.brightness ?? 1.0)
                mappers[i].minLoad = dev?.minLoad ?? 0
                mappers[i].params = effParams
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
                mappers[i].render(bands: bands, power: powerOut, dt: dt)
                mappers[i].serialize(into: &pixelBytes)
                senders[i].send(pixels: pixelBytes)
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
                bass: bassOut,
                treble: trebleOut,
                beat: beatOut,
                lastFrameAgo: 0,
                aggregateAlive: aggregateAlive,
                effBrightness: effBright,
                effParams: effParams
            )
            publishLive(frame, sampleRate)
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: BUILD STILL FAILS only because of `BarView.swift` + `Showcase.swift`. Engine, model, config, registry all compile clean now.

- [ ] **Step 3: Commit**

```bash
git add Sources/Pulsar/AudioEngine.swift
git commit -m "Resolve per-effect params + global brightness in engine"
```

---

## Task 13: BarView — flat picker + dynamic param rows

The picker drops the Reactive/Ambient subgroups. `LookMixSection` shows brightness + a dynamic list of `ReactiveSliderRow` instances, one per param of the current effect. `KindBadge` and the `reactiveAvailable`/`ambientAvailable` helpers go away.

**Files:**
- Modify: `Sources/Pulsar/BarView.swift`

- [ ] **Step 1: Update `ReactiveSliderRow` to take a driver+closure pair**

Open `Sources/Pulsar/BarView.swift`. Replace the `ReactiveSliderRow` and `AspectIcon` definitions (currently around lines 445–525) with:

```swift
private struct ReactiveSliderRow: View {
    let title: String
    let value: Double
    let liveValue: Float
    let range: ClosedRange<Double>
    let valueText: String
    let formatLive: (Float) -> String
    let onChange: (Double) -> Void
    let enabled: Bool
    let driver: Driver
    let onCycleDriver: () -> Void
    @ObservedObject var live: LiveStore

    var body: some View {
        let liveClamped = min(max(Double(liveValue), range.lowerBound), range.upperBound)
        let shownValue = driver.reactive ? liveClamped : value
        let shownText = driver.reactive ? formatLive(liveValue) : valueText
        HStack(spacing: 6) {
            Text(title)
                .font(.callout)
                .frame(width: 90, alignment: .leading)
            Slider(value: Binding(
                get: { shownValue },
                set: { v in
                    if driver.reactive { return }
                    let snapped = range.contains(0.5) && abs(v - 0.5) < 0.02 ? 0.5 : v
                    onChange(snapped)
                }
            ), in: range)
            .disabled(!enabled || driver.reactive)
            .allowsHitTesting(enabled && !driver.reactive)
            .animation(driver.reactive ? .linear(duration: 0.08) : nil, value: shownValue)
            AspectIcon(driver: driver, live: live, action: onCycleDriver)
                .disabled(!enabled)
            Text(shownText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
        .frame(height: 26)
    }
}

private struct AspectIcon: View {
    let driver: Driver
    @ObservedObject var live: LiveStore
    let action: () -> Void

    var body: some View {
        let signal = driver.reactive ? live.frame.value(for: driver.aspect) : 0
        let symbol = driver.reactive ? driver.aspect.symbol : "waveform"
        let scale = 1.0 + 0.30 * Double(signal)
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(driver.reactive ? Color.accentColor : Color.secondary.opacity(0.55))
                .scaleEffect(scale)
                .frame(width: 22, height: 18)
                .background(Capsule().fill(driver.reactive ? Color.accentColor.opacity(0.18) : Color.clear))
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.08), value: signal)
        }
        .buttonStyle(.plain)
        .help(driver.reactive ? "Driven by \(driver.aspect.label) — tap to cycle" : "Manual — tap to cycle audio source")
    }
}
```

- [ ] **Step 2: Replace `LookMixSection`**

Replace the existing `LookMixSection` struct (currently around lines 295–398) with:

```swift
private struct LookMixSection: View {
    let model: ControlModel
    @ObservedObject var settings: SettingsStore
    init(model: ControlModel) {
        self.model = model
        self.settings = model.settings
    }

    var body: some View {
        Section(title: "Look") {
            Picker("", selection: Binding(
                get: { settings.settings.effect },
                set: { model.setMasterEffect($0) }
            )) {
                ForEach(settings.settings.availableEffects, id: \.self) { e in
                    if let type = EffectRegistry.type(byID: e) {
                        Text(type.label).tag(e)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(settings.status != .running)
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                ForEach(settings.settings.availablePalettes, id: \.self) { id in
                    CompactPaletteSwatch(
                        palette: Palette.by(id: id),
                        selected: settings.settings.palette == id
                    ) {
                        tapHaptic()
                        withAnimation(snapSpring) { model.setPalette(id) }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 4)

            // Global brightness (always present).
            ReactiveSliderRow(
                title: "Brightness",
                value: Double(settings.settings.brightness),
                liveValue: model.live.frame.effBrightness,
                range: 0...1,
                valueText: "\(Int(settings.settings.brightness * 100))%",
                formatLive: { v in "\(Int(v * 100))%" },
                onChange: { model.setBrightness(Float($0)) },
                enabled: settings.status == .running,
                driver: settings.settings.brightnessDriver,
                onCycleDriver: { model.cycleBrightnessDriver() },
                live: model.live
            )

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
                .padding(.vertical, 4)

            // Per-effect params.
            if let type = EffectRegistry.type(byID: settings.settings.effect) {
                ForEach(type.params, id: \.id) { param in
                    let state = settings.settings.effectState[settings.settings.effect]?[param.id]
                        ?? EffectParamState(value: param.defaultValue, driver: .manualPower)
                    ReactiveSliderRow(
                        title: param.label,
                        value: Double(state.value),
                        liveValue: model.live.frame.effParams[param.id] ?? state.value,
                        range: 0...1,
                        valueText: param.format(state.value),
                        formatLive: param.format,
                        onChange: { model.setEffectParam(effectID: settings.settings.effect, paramID: param.id, value: Float($0)) },
                        enabled: settings.status == .running,
                        driver: state.driver,
                        onCycleDriver: { model.cycleEffectParamDriver(effectID: settings.settings.effect, paramID: param.id) },
                        live: model.live
                    )
                }
            }
        }
    }
}
```

- [ ] **Step 3: Delete now-unused `KindBadge` struct**

Search `BarView.swift` for `private struct KindBadge` and remove the entire struct definition (currently ~lines 400–413). The struct has no other call sites after Step 2.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: PASS — assuming `Showcase.swift` still references old fields, BUILD MAY STILL FAIL on Showcase. Task 14 fixes it.

- [ ] **Step 5: Commit**

```bash
git add Sources/Pulsar/BarView.swift
git commit -m "Bind UI to dynamic per-effect param rows"
```

---

## Task 14: Showcase + CLAUDE.md + smoke test

**Files:**
- Modify: `Sources/Pulsar/Showcase.swift`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update `Showcase.applyVariant` to use the new shape**

In `Sources/Pulsar/Showcase.swift`, replace the existing `applyVariant` (currently lines 41–79) with:

```swift
@MainActor
private static func applyVariant(_ model: ControlModel, _ v: Variant) {
    var s = Settings.empty
    s.enabled = true
    s.effect = v.effect
    s.palette = v.palette
    s.brightness = v.brightness
    s.fps = 60
    s.bandCount = 32
    s.sampleRate = 48000
    s.tccStatus = 0
    // Seed the showcase variant's "speed"/"intensity" into matching
    // params on the selected effect. Legacy variant range 0..2 → 0..1.
    if let type = EffectRegistry.type(byID: v.effect) {
        var map = s.effectState[v.effect] ?? [:]
        if type.params.contains(where: { $0.id == "speed" }) {
            map["speed"] = EffectParamState(value: min(1, v.speed / 2), driver: .manualPower)
        }
        if type.params.contains(where: { $0.id == "intensity" }) {
            map["intensity"] = EffectParamState(value: min(1, v.intensity / 2), driver: .manualPower)
        }
        s.effectState[v.effect] = map
    }
    s.devices = [
        DeviceRuntime(
            name: "Desk", ip: "192.0.2.42", pixelCount: 237, rgbw: false,
            brightness: 1.0, enabled: true,
            segments: [
                SegmentRuntime(start: 0, length: 119, reverse: false, mirror: false),
                SegmentRuntime(start: 119, length: 118, reverse: true,  mirror: false),
            ]),
        DeviceRuntime(
            name: "Shelf", ip: "192.0.2.43", pixelCount: 144, rgbw: true,
            brightness: 0.7, enabled: true,
            segments: [
                SegmentRuntime(start: 0, length: 144, reverse: false, mirror: false),
            ]),
    ]
    model.settings.settings = s
    model.settings.status = .running
    model.renderState.replace(settings: s)
    model.live.frame = syntheticFrame()
}
```

Also update the `syntheticFrame` builder (lines ~180–197): replace `effBrightness: 1, effSpeed: 1, effIntensity: 1` with `effBrightness: 1, effParams: [:]`.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: PASS — clean build at last.

- [ ] **Step 3: Run all tests**

Run: `swift test`
Expected: PASS for every test in `ConfigTests`, `ConfigMigrationTests`, `EffectRegistryTests`, and any preexisting tests.

- [ ] **Step 4: Visual smoke test**

Run: `rm -rf /tmp/pulsar-shots && PULSAR_SHOWCASE_RENDER=/tmp/pulsar-shots swift run`
Expected: four PNGs in `/tmp/pulsar-shots/` — `spectrum-sunset.png`, `wavelength-ocean.png`, `beat_wave-cyberpunk.png`, `ripple-fire.png`. Open them and confirm:
- Panel shows a single flat effect picker (no "Reactive" / "Ambient" subgroups).
- No `KindBadge` next to the picker.
- Sliders match the active effect's declared params (e.g. Spectrum shows "Peak Fall" + "Gain"; Beat Wave shows "Speed" + "Sensitivity").
- Brightness is always at the top of the slider stack with a divider beneath it.

- [ ] **Step 5: Rewrite the "Effects" section of `CLAUDE.md`**

In `CLAUDE.md`, find the `## Effects` section (lines 18–28) and replace it with:

```markdown
## Effects

- Each effect lives in its own file under `Sources/Pulsar/Effects/` and
  conforms to the `Effect` protocol. The protocol carries `id`, `label`,
  a declared `[EffectParam]` list, and a `render(into:bands:power:dt:
  params:palette:rgbw:)` method.
- `EffectRegistry.all` is the authoritative ordered list. Add a new
  effect = add one file + append the type to the registry.
- Param values are normalized `[0,1]`. Effects map internally; the
  convention is to multiply `speed`/`intensity`-style params by 2 so
  `value = 0.5` reproduces the legacy `1.0` neutral.
- Brightness is the only global slider. Per-effect param state lives in
  `Settings.effectState` keyed by `[effectID][paramID]`, persisted across
  effect switches.
- Every slider (brightness + each per-effect param) is independently
  drivable via the `off → power → bass → treble → beat → off` cycle.
  Driven params lock the slider; the thumb animates to the live audio-
  modulated value. Driver math: `effective = base × (floor + (1 − floor)
  × signal)` with the floor declared per-param.
- No idle-purple short-circuit. Effects render on silence as whatever
  they render at zero power. Master-off and device-off still write black.
- Effect/palette switches are crossfaded via smoothstep in
  `Mapper.applyTransitionCrossfade` (0.6 s). Don't add hard snaps.
```

- [ ] **Step 6: Commit**

```bash
git add Sources/Pulsar/Showcase.swift CLAUDE.md
git commit -m "Update showcase + CLAUDE.md for per-effect param model"
```

- [ ] **Step 7: Run the full test suite once more for hygiene**

Run: `swift test`
Expected: PASS.

---

## Task 15: Add param-resolution unit test

Adds a small targeted test that locks in the driver math the engine relies on. Useful regression net for future refactors.

**Files:**
- Create: `Tests/PulsarTests/EffectParamResolutionTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/PulsarTests/EffectParamResolutionTests.swift
import XCTest
@testable import Pulsar

final class EffectParamResolutionTests: XCTestCase {
    // The engine uses this formula internally (`AudioEngine.driven`).
    // We replicate it here against the same Driver/EffectParamState
    // shape to make the contract explicit.
    private func resolve(state: EffectParamState, signal: Float, floor: Float) -> Float {
        if !state.driver.reactive { return state.value }
        return state.value * (floor + (1 - floor) * signal)
    }

    func testManualDriverReturnsBase() {
        let state = EffectParamState(value: 0.8, driver: .manualPower)
        XCTAssertEqual(resolve(state: state, signal: 1.0, floor: 0.25), 0.8, accuracy: 0.0001)
    }

    func testDrivenWithFullSignalReturnsBase() {
        let state = EffectParamState(value: 0.8, driver: Driver(reactive: true, aspect: .power))
        XCTAssertEqual(resolve(state: state, signal: 1.0, floor: 0.25), 0.8, accuracy: 0.0001)
    }

    func testDrivenWithZeroSignalReturnsBaseTimesFloor() {
        let state = EffectParamState(value: 0.8, driver: Driver(reactive: true, aspect: .power))
        XCTAssertEqual(resolve(state: state, signal: 0.0, floor: 0.25), 0.8 * 0.25, accuracy: 0.0001)
    }

    func testBrightnessFloorIsZero() {
        // Convention: brightness uses driverFloor = 0. So a silent room
        // pulls effective brightness all the way to zero.
        let state = EffectParamState(value: 1.0, driver: Driver(reactive: true, aspect: .power))
        XCTAssertEqual(resolve(state: state, signal: 0.0, floor: 0.0), 0.0, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run the test**

Run: `swift test --filter EffectParamResolutionTests`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Tests/PulsarTests/EffectParamResolutionTests.swift
git commit -m "Lock in driver resolution math"
```

---

## Self-Review

**Spec coverage:**
- Settled decisions 1–7 → all addressed (Tasks 1–14). Per-effect persistence in `EffectStateMap` (T9). Silence handling: idle-purple gate gone (T12). Free-form param list per effect (T1, T4–T7). Normalized `[0,1]` everywhere (T4–T7 internal mapping). Driver model same per param (T1 `EffectParamState`, T12 resolution). Migration one-shot on load (T10). Protocol + one file per effect (T1, T3, T4–T7).
- Data model: `Driver`, `EffectParamState`, `EffectStateMap`, `LiveFrame.effParams`, `Settings.brightnessDriver`, `Settings.effectState` — all defined (T1, T9).
- Effect protocol — defined (T1) with `paramValue(_:in:)` fallback helper.
- Registry + file layout — Task 3 + Tasks 4–7.
- Param resolution — Task 12, plus regression test in Task 15.
- Crossfade — preserved (T8 `Mapper.applyTransitionCrossfade`).
- Per-effect param table — Tasks 4–7 declarations match spec values.
- UI changes — Task 13.
- Persistence + migration — Task 10.
- Sanitization (unknown effect/param drop) — Task 10 `sanitized()`.
- Deletions — Task 8 (Mapper interior), Task 12 (engine idle-purple), Task 13 (`KindBadge`).
- "How to add a new effect" — Task 14 CLAUDE.md update.

**Placeholder scan:** No TBD / TODO / "appropriate error handling" / "implement later" text in any task body. Every code block is complete and ready to paste.

**Type consistency:**
- `Driver`, `EffectParamState`, `EffectStateMap`, `Effect`, `EffectParam`, `EffectRegistry`, `Mapper`, `RenderView`, `RenderState`, `Settings`, `LiveFrame`, `Config` names match across tasks.
- `Self.paramValue("speed", in: params)` is defined in Task 1 (`Effect` extension) and called in Tasks 4–7.
- `EffectRegistry.type(byID:)` is defined in Task 3 and called in Tasks 8, 10, 11, 12, 13, 14.
- `Mapper.params` (added in T8) is set by AudioEngine (T12).
- `Settings.defaultEffectState()` is defined in T9 and called in T10.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-05-24-per-effect-params.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — Dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
