# Reactive sliders — design

Per-slider audio reactivity for Brightness, Speed, and Intensity in the
menu-bar panel. Each slider gains:

- a **waveform pill** toggle that makes the slider react to a chosen
  audio aspect; and
- a **gear** popover that picks which aspect drives that slider
  (Power / Bass / Treble / Beat Onset).

Slider value becomes the *cap*: effective = aspect × sliderValue.

## Goals

1. Let users opt any of Brightness / Speed / Intensity into audio
   modulation without affecting the other two.
2. Expose a meaningful set of audio aspects, not just RMS.
3. Visualise that a slider is reactive (waveform pill pulses with the
   live aspect signal).
4. Persist binding + aspect across launches.

## Non-goals

- Custom envelopes (attack / release knobs).
- Per-aspect smoothing controls.
- Inverted reactivity (loud → low).
- Mapping any setting other than the three primary sliders.

## Data model

New enum:

```swift
enum AudioAspect: String, Codable, CaseIterable {
    case power, bass, treble, beat
}
```

New struct:

```swift
struct AudioFeatures {
    var power: Float   // smoothed RMS, [0,1]
    var bass: Float    // mean of bottom quartile band, [0,1]
    var treble: Float  // mean of top quartile band, [0,1]
    var beat: Float    // decaying pulse, [0,1], spikes on beat
}
```

Extend `ControlModel.Snapshot`:

```swift
var brightnessReactive: Bool
var brightnessAspect: AudioAspect
var speedReactive: Bool
var speedAspect: AudioAspect
var intensityReactive: Bool
var intensityAspect: AudioAspect
```

Defaults: `reactive = false`, `aspect = .power`.

Extend `Config` mirror fields with the same defaults so older configs
load cleanly (missing → default).

## Audio pipeline

`AudioEngine.run` computes `AudioFeatures` per frame:

- `power` — existing RMS.
- `bass` — `bands[0 ..< bands.count/4]` mean.
- `treble` — `bands[3*bands.count/4 ..< bands.count]` mean.
- `beat` — state on AudioEngine: spike to 1 when `BeatDetector.update`
  returns true; otherwise multiply by `expf(-dt * 2.5)`.

Each component clamped to [0,1] after light gain (matching existing
spectrum gain conventions, see `renderSpectrum`).

`AudioFeatures` is published on `ControlModel` (`@Published var
features: AudioFeatures`) on the main actor, so SwiftUI can drive the
waveform-pill pulse animation.

## Modulation point

In `AudioEngine.run`, just before assigning the per-mapper scalars:

```swift
let bAsp = aspectValue(view.brightnessAspect, features)
let sAsp = aspectValue(view.speedAspect, features)
let iAsp = aspectValue(view.intensityAspect, features)

let effBrightness = view.brightnessReactive
    ? view.brightness * bAsp : view.brightness
let effSpeed = view.speedReactive
    ? max(0.05, view.speed * sAsp) : view.speed
let effIntensity = view.intensityReactive
    ? view.intensity * iAsp : view.intensity

mappers[i].brightness = effBrightness * (dev?.brightness ?? 1.0)
mappers[i].speed = effSpeed
mappers[i].intensity = effIntensity
```

Floors: brightness allowed to reach 0 (intentional — silent = dark when
opted in). Speed floored at 0.05 so animations don't freeze entirely.
Intensity allowed to reach 0.

## UI

New view `ReactiveSliderRow`:

```
[ Brightness ] [≈]  ━━━━●━━━  [⚙]  100%
[ Speed      ] [≈]  ━━●━━━━━  [⚙]  1.00x
[ Intensity  ] [≈]  ●━━━━━━━  [⚙]  0.10x
```

- **Waveform pill** — SF Symbol `waveform`, leading position. Tinted
  accent + faint glow when reactive. Scale modulated by `features.<aspect>`
  (1.0 + 0.25 × signal) via implicit animation. Tap toggles reactive.
- **Slider** — unchanged.
- **Gear** — SF Symbol `gearshape`. Tap opens Popover with radio list
  of `AudioAspect.allCases`. Disabled (greyed) when reactive=false.
- **Value text** — dimmed (secondary colour) when reactive, signalling
  it represents the cap rather than the current value.

`BarView` replaces the three current `LabeledSlider` rows with
`ReactiveSliderRow` instances bound to the new ControlModel fields.

## Persistence

`Config.swift` gains optional fields for each `reactive` flag and
`aspect` string. Encoders write current values; decoders default to
non-reactive on missing keys. No migration script needed.

## Testing

- Build: `./scripts/build.sh` produces app bundle.
- Smoke: launch app, switch effect to Spectrum, toggle Brightness pill,
  verify waveform pulses with playback and strip brightness tracks RMS
  up to the cap.
- Aspect swap: pick Bass via gear, play bass-heavy track, verify only
  low frequencies drive the slider.
- Persistence: relaunch and verify toggles + selected aspects survive.

## Files touched

- `Sources/Pulsar/Models.swift` — `AudioAspect`, `AudioFeatures`,
  Snapshot fields.
- `Sources/Pulsar/Config.swift` — persisted reactive / aspect fields.
- `Sources/Pulsar/ControlModel.swift` — state, published features,
  setters.
- `Sources/Pulsar/AudioEngine.swift` — features computation,
  modulation hook.
- `Sources/Pulsar/BarView.swift` — `ReactiveSliderRow` view, gear
  popover, replace slider rows.
