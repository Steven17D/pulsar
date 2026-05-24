# Per-Effect Params + Unified Reactivity — Design

Date: 2026-05-24
Status: Approved, ready for implementation plan.

## Goal

Collapse the reactive/ambient distinction. Every effect is "the same shape":
it declares its own set of sliders, each slider can be driven by audio (same
mechanism as today), and there is a single global brightness slider above
the per-effect set. Establish a consistent, low-ceremony interface and file
convention for declaring new effects.

## Non-goals

- Change the audio pipeline (FFT, bands, beat detector, aspect signals).
- Change the segment serialization, mirror/reverse, or device model.
- Change the crossfade transition between effects/palettes.
- Introduce per-device effects (effect remains single, global).

## Settled decisions

These are the answers from the brainstorming pass; the design rests on them.

1. **Param scope:** per-effect. Each effect has its own values that persist
   across switches, so flipping from `plasma` to `spectrum` and back restores
   each effect's settings.
2. **Silence handling:** no idle-purple, no ambient gate. Effects render
   whatever they render at zero audio. Master-off and device-off still
   write black.
3. **Slider declaration:** free-form param list per effect — declaration
   order is UI order, names are arbitrary, no fixed slots.
4. **Param range:** normalized `[0,1]` everywhere. The effect maps to its
   internal natural unit. Drivers stay range-agnostic.
5. **Driver model:** unchanged from today. Per-param `reactive`/`aspect`
   state. Driven param: `effective = base × (floor + (1 − floor) × signal)`
   with the floor declared per-param. Slider locks while driven; thumb
   animates to the live value.
6. **Migration:** one-shot on `Config.load()`. Old top-level
   `speed`/`intensity`/`*_reactive`/`*_aspect` are folded into the current
   effect's per-effect param state, then dropped on next save.
7. **Effect location:** `Effect` protocol; one file per effect under
   `Sources/Pulsar/Effects/`. `Mapper` becomes a thin driver.

## Architecture

### Data model

```swift
enum AudioAspect: String, Codable, CaseIterable { case power, bass, treble, beat }

struct Driver: Codable, Equatable {
    var reactive: Bool
    var aspect: AudioAspect
}

struct EffectParamState: Codable, Equatable {
    var value: Float        // 0..1, user base value
    var driver: Driver
}

// Persisted: one entry per (effectID, paramID). Across switches.
typealias EffectStateMap = [String: [String: EffectParamState]]
```

`Settings` (runtime) and `Config` (on-disk) both carry:
- `enabled: Bool`
- `effect: String`
- `palette: String`
- `brightness: Float`             // global, 0..1
- `brightnessDriver: Driver`      // global
- `effectState: EffectStateMap`   // every effect's params
- `devices: [DeviceRuntime]`      // unchanged

The old top-level `speed`, `intensity`, `*_reactive`, `*_aspect` are removed
from the in-memory model. They live only in `Config.load()` for migration.

### Effect protocol

```swift
struct EffectParam {
    let id: String                       // stable wire id, e.g. "speed"
    let label: String                    // UI label, e.g. "Speed"
    let defaultValue: Float              // 0..1
    let driverFloor: Float               // 0..1, used when reactive
    let format: (Float) -> String        // value → UI display, e.g. "50%"
}

protocol Effect: AnyObject {
    static var id: String { get }                  // wire id
    static var label: String { get }               // pretty label
    static var params: [EffectParam] { get }       // declaration order = UI order

    init(renderLen: Int)
    func resize(_ renderLen: Int)
    func render(into pixels: inout [Pixel],
                bands: [Float], power: Float, dt: Float,
                params: [String: Float],
                palette: Palette, rgbw: Bool)
}
```

The `params` dict handed to `render` contains already-driven, post-floor
values in `[0,1]`. The effect is responsible for mapping each into its
natural unit (e.g. multiply by 2 for a 0..2 internal range). Effects MUST
use `params[id, default: <declared default>]` so a missing key never traps.

Stable param ids are recommended where the meaning is universal:
- `speed`     — generic time/phase rate
- `intensity` — generic amplitude/gain knob

These are conventions, not requirements. An effect can pick any id.

### Registry

```swift
enum EffectRegistry {
    static let all: [Effect.Type] = [
        TestEffect.self, SolidEffect.self, RainbowEffect.self,
        BreatheEffect.self, CometEffect.self, PlasmaEffect.self,
        SpectrumEffect.self, WavelengthEffect.self,
        BeatWaveEffect.self, RippleEffect.self, GlitterEffect.self,
    ]
    static var availableIDs: [String] { all.map(\.id) }
    static func type(byID id: String) -> Effect.Type {
        all.first { $0.id == id } ?? SpectrumEffect.self
    }
}
```

Adding a new effect = add one file under `Sources/Pulsar/Effects/`, add the
class to `EffectRegistry.all`. No other site edits.

### File layout

```
Sources/Pulsar/Effects/
    Effect.swift              // protocol + EffectParam + helpers
    Registry.swift            // EffectRegistry
    Shared.swift              // BeatDetector, Pixel helpers (paletteSeamless, hsvToRGB, fromRGB, addPixels)
    Test.swift                // TestEffect
    Solid.swift               // SolidEffect
    Rainbow.swift             // RainbowEffect
    Breathe.swift             // BreatheEffect
    Comet.swift               // CometEffect
    Plasma.swift              // PlasmaEffect
    Spectrum.swift            // SpectrumEffect
    Wavelength.swift          // WavelengthEffect
    BeatWave.swift            // BeatWaveEffect
    Ripple.swift              // RippleEffect
    Glitter.swift             // GlitterEffect
```

`Mapper.swift` shrinks to: `Pixel` type, pixel buffer + render length
tracking, current effect instance ownership, the crossfade snapshot/
blend, and `serialize(into:)` / `writeBlack(into:)` / `writeSolid(...)`.
It no longer contains `renderXxx` methods, `reactiveEffects`,
`ambientEffects`, `isAmbient`, or `pretty`.

### Param resolution (engine)

`AudioEngine.run`, per tick:

1. Read `view = renderState.snapshot()` — includes current effect id,
   global brightness + driver, and the params + drivers for the current
   effect.
2. Compute aspect signals (`powerOut`, `bassOut`, `trebleOut`, `beatOut`)
   as today.
3. Resolve brightness:
   ```
   effBright = view.brightnessDriver.reactive
       ? view.brightness * aspectSignal(view.brightnessDriver.aspect)
       : view.brightness
   ```
   (Floor 0 — quiet rooms stay visibly dark.)
4. Resolve each param `p` of the current effect:
   ```
   sig = aspectSignal(p.driver.aspect)
   eff = p.driver.reactive
       ? p.value * (p.floor + (1 - p.floor) * sig)
       : p.value
   ```
   Build `[paramID: eff]`.
5. Hand the dict to the effect's `render(...)`. No silence gate, no
   ambient gate, no idle-purple short-circuit. Master-off and per-device-off
   still write black (preserved).
6. Publish `LiveFrame` with `effBrightness` plus `effParams: [String: Float]`
   so the UI can animate locked sliders.

### Crossfade

Unchanged. `Mapper` keeps the `transitionFrom` snapshot and the smoothstep
blend in `applyTransitionCrossfade`. It triggers on effect id change or
palette id change exactly as today.

### Per-effect param table

Defaults are tuned so each effect's behavior at `value = 0.5` matches
its behavior today at `speed = 1.0` / `intensity = 1.0` (i.e. the effect
internally remaps 0..1 → its old natural range).

| Effect       | Params (id : label : default : floor)                                       |
|--------------|------------------------------------------------------------------------------|
| `test`       | (none)                                                                       |
| `solid`      | `speed`:Speed:0.5:0.25 — `intensity`:Intensity:0.5:0.20                      |
| `rainbow`    | `speed`:Speed:0.5:0.25 — `cycles`:Cycles:0.4:0.00                            |
| `breathe`    | `speed`:Speed:0.5:0.25 — `intensity`:Intensity:0.5:0.20                      |
| `comet`      | `speed`:Speed:0.5:0.25 — `tail`:Tail:0.5:0.00                                |
| `plasma`     | `speed`:Speed:0.5:0.25 — `boost`:Audio Boost:0.5:0.20                        |
| `spectrum`   | `peakFall`:Peak Fall:0.5:0.25 — `gain`:Gain:0.5:0.20                         |
| `wavelength` | `speed`:Speed:0.5:0.25 — `gain`:Gain:0.5:0.20                                |
| `beat_wave`  | `speed`:Speed:0.5:0.25 — `sensitivity`:Sensitivity:0.5:0.20                  |
| `ripple`     | `speed`:Speed:0.5:0.25 — `sensitivity`:Sensitivity:0.5:0.20                  |
| `glitter`    | `decay`:Decay:0.5:0.25 — `density`:Density:0.5:0.20                          |

Format closures live in a `EffectParam.pct` / `EffectParam.mult` helper set
(percent display vs. `1.0x`-style multiplier display).

## UI changes (BarView)

`LookMixSection` becomes:

1. **Effect picker** — flat list (no Reactive/Ambient subgroups), labels
   from `EffectType.label`. The `KindBadge` ("Reactive"/"Ambient") is
   removed.
2. **Palette swatch row** — unchanged.
3. **Brightness `ReactiveSliderRow`** — always present, bound to the
   global `brightness` + `brightnessDriver`.
4. **Hairline divider** between brightness and per-effect params.
5. **For each param of the current effect**: one `ReactiveSliderRow`
   bound to `effectState[effect][paramID]`.

`ReactiveSliderRow` is generalised: it takes a `Driver` plus a closure
that knows how to cycle that driver (mirrors today's
`cycleBrightnessDriver`). The row reads the live value from
`LiveFrame.effParams[paramID]` (or `effBrightness` for the global slider)
to animate the locked thumb.

The picker's `disabled` / `enabled` rules and the row's master-off
behaviour stay as today.

## Persistence

### Schema (new)

```json
{
  "fps": 60,
  "fft_size": 1024,
  "band_count": 32,
  "smoothing": 0.6,
  "min_freq_hz": 40,
  "max_freq_hz": 16000,
  "enabled": true,
  "effect": "spectrum",
  "palette": "sunset",
  "brightness": 1.0,
  "brightness_driver": { "reactive": false, "aspect": "power" },
  "effect_state": {
    "spectrum": {
      "gain":     { "value": 0.5, "driver": { "reactive": true,  "aspect": "power" } },
      "peakFall": { "value": 0.5, "driver": { "reactive": false, "aspect": "power" } }
    },
    "plasma": {
      "speed":    { "value": 0.5, "driver": { "reactive": false, "aspect": "power" } },
      "boost":    { "value": 0.5, "driver": { "reactive": true,  "aspect": "bass"  } }
    }
  },
  "devices": [ ... unchanged ... ]
}
```

### Migration (one-shot on load)

`Config.load()`:

1. If the parsed config has a `brightness_driver`, use it. Otherwise build
   one from the legacy `brightness_reactive` + `brightness_aspect`, falling
   back to `{reactive: false, aspect: .power}`.
2. If the parsed config has an `effect_state`, use it. Otherwise build a
   fresh map: for every `Effect.Type` in `EffectRegistry.all`, populate
   each declared param with its `defaultValue` + `{reactive: false, aspect:
   .power}`.
3. For the **currently selected effect**: if legacy `speed`/`intensity`
   exist, write them into that effect's `speed` and `intensity` params
   when those param ids are present. The legacy `0..2` range maps to
   `[0,1]` via `min(1.0, legacy / 2.0)` so `legacy = 1.0` → new `0.5`
   (preserves the "neutral" baseline). Same for the legacy `speed_reactive`
   /`speed_aspect` and `intensity_*` fields, written into the corresponding
   param's `driver`.
4. Effects with no `speed` or no `intensity` param (e.g. `spectrum` has
   `gain` + `peakFall`, not `intensity`/`speed`) silently skip the legacy
   write — defaults stand.
5. On save: only the new schema is written. Old fields are dropped.

### Sanitization

Unknown effect ids in `effect_state` are dropped on save. Unknown param
ids inside a known effect are dropped on save. Values are clamped to
`[0,1]`. `Driver.aspect` falls back to `.power` if it doesn't parse.

## What gets deleted

- `Mapper.reactiveEffects`, `Mapper.ambientEffects`, `Mapper.isAmbient(_:)`,
  `Mapper.pretty(_:)`.
- `Mapper.renderTest/Solid/Rainbow/Breathe/Comet/Plasma/Spectrum/`
  `Wavelength/BeatWave/Ripple/Glitter` — relocated to one file each.
- `AudioEngine` blocks computing `effectIsAmbient`, `reactiveSilent`,
  `anyReactive`, `effPower`-gating, and the idle-purple `writeSolid`.
- `Settings.speed`, `Settings.intensity`, `Settings.brightnessReactive`,
  `Settings.brightnessAspect`, `Settings.speedReactive`,
  `Settings.speedAspect`, `Settings.intensityReactive`,
  `Settings.intensityAspect` and matching fields on `RenderState`.
- `ControlModel.setSpeed`, `setIntensity`, `setBrightnessReactive`,
  `setBrightnessAspect`, `setSpeedReactive`, `setSpeedAspect`,
  `setIntensityReactive`, `setIntensityAspect`, `cycleBrightnessDriver`,
  `cycleSpeedDriver`, `cycleIntensityDriver` — replaced by a uniform
  `setEffectParam(effectID, paramID, value)`, `cycleEffectParamDriver(...)`,
  plus `setBrightness`, `cycleBrightnessDriver` (kept).

The uniform setters take an explicit `effectID` so they can write to any
effect's stored params (not only the active one). The UI only ever
exposes the active effect's params, but the API stays symmetric.
- `Settings.empty.brightnessAspect`/`speedAspect`/`intensityAspect`
  defaults — superseded.
- `LiveFrame.effSpeed`, `LiveFrame.effIntensity` — replaced by
  `LiveFrame.effParams`.
- CLAUDE.md "Effects" section — rewritten to describe the new model.

## What stays

- `Pixel`, segment serialize, mirror/reverse, `minLoad` two-stage load
  floor, RGBW handling, DDP sender, beat detector logic (`BeatDetector`),
  crossfade, palette system, audio pipeline, device CRUD.
- The driver-cycle state machine (`off → power → bass → treble → beat →
  off`) — same function, applied uniformly to every param.

## Testing strategy

- Existing unit tests under `Tests/` continue to assert behaviour of
  things that survive: segment serialization, palette sampling, beat
  detector, config sanitization, idle floors.
- New unit tests:
  - **Migration**: feed a legacy config blob in, assert the resulting
    `Settings.effectState` carries the expected values, drivers, and
    skips effects with no matching param.
  - **Effect registry**: every entry in `EffectRegistry.all` returns a
    non-empty `id`, `label`, `params`; all `params` have unique ids
    within an effect; defaults and floors are in `[0,1]`.
  - **Param resolution**: given a synthetic `Driver` + signal, assert
    the engine produces `base * (floor + (1 - floor) * signal)`.
  - **Effect contract**: each `Effect` renders without trapping when
    `params` is empty (missing-key fallback path).
- Manual visual check via `PULSAR_SHOWCASE=1` and
  `PULSAR_SHOWCASE_RENDER=<dir>` to confirm no regression in the four
  showcased combinations (`spectrum/sunset`, `wavelength/ocean`,
  `beat_wave/cyberpunk`, `ripple/fire`).

## Risks & open notes

- **Visual drift on migration**: mapping legacy `1.0` → new `0.5` keeps
  the neutral baseline but does not perfectly preserve effect-specific
  tuning when an old user set e.g. `intensity = 1.8`. Acceptable —
  documented in the rewritten CLAUDE.md.
- **Showcase fixtures** (`Showcase.applyVariant`) currently push
  `speed`/`intensity` directly. They must be updated to seed
  `Settings.effectState` (or simply leave defaults). `Settings.empty`
  must build a fresh `effectState` from `EffectRegistry` at static-init
  time so any code path that constructs an empty Settings has a valid
  map.
- The protocol uses class types (`AnyObject`) because effects own mutable
  per-instance state (phase, particle lists). Each effect is recreated
  on switch, mirroring today's behaviour of resetting wave/ripple/twinkle
  lists when the renderLen changes.

## How to add a new effect (the convention)

1. Create `Sources/Pulsar/Effects/<Name>.swift`.
2. Implement `Effect` — pick a stable `id`, a `label`, declare `params`
   (use `speed`/`intensity` ids when the meaning matches), implement
   `init`, `resize`, `render`.
3. Add the type to `EffectRegistry.all`.
4. No other edits — UI, persistence, drivers, migration handle the new
   effect automatically.
