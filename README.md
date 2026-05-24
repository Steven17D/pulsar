# Pulsar

Audio-reactive WLED controller for macOS. Taps the system audio output
via Core Audio's Process Tap API (macOS 14.4+), runs an FFT, and pushes
DDP/UDP frames to one or more WLED controllers at 60 Hz. Lives in the
menu bar; the system default output stays a real device so native
volume keys and the macOS OSD keep working.

> **Status:** alpha. The core pipeline (tap → FFT → DDP) is stable;
> APIs around the config file and effect list will still move.

## Why

Most LED-sync setups for WLED on macOS go through LedFx or BlackHole,
either of which requires hijacking the system default output device. Pulsar
uses the **Process Tap API** introduced in macOS 14.4, which reads from
whatever device is currently active without redirecting it — no virtual
device, no volume-key intercept, no per-app loopback configuration.

## Features

- **Process Tap audio capture** (macOS 14.4+). Reads whatever is playing
  out of the user's selected output device, including Bluetooth speakers.
- **5 palettes**: Sunset, Ocean, Forest, Cyberpunk, Fire.
- **5 reactive effects**: Spectrum Bars (with peak hold), Wavelength
  (scrolling palette), Beat Wave (onset-spawned travelling waves),
  Ripple (bass-kick radial pulses), Glitter (palette base + twinkles).
  Plus a Test diagnostic and a Solid ambient mode.
- **Per-strip on/off**, per-strip brightness, segment-level reverse +
  in-segment mirror — segments are auto-discovered from each WLED via
  `/json/cfg`.
- **Speed + Intensity** sliders. Snap to 1.0× when released near the
  default; tap the value label to reset.
- **Multi-device**: drives any number of WLED controllers in parallel
  over UDP DDP (RGB or RGBW).
- **SwiftUI menu-bar panel** with live spectrum + power meter previewing
  the active palette.
- **Self-healing**: monitors `kAudioDevicePropertyDeviceIsAlive` once a
  second and respawns the engine on coreaudiod restart / default-output
  swap. Retries `AudioDeviceStart` through the transient `"nope"`
  errors coreaudiod returns for ~1–2 s after a teardown.

## Requirements

- macOS 14.4 or later (Process Tap API).
- Xcode Command Line Tools (`xcode-select --install`).
- One or more WLED controllers reachable over the LAN, accepting DDP
  realtime on UDP/4048.

## Install

Clone and run the build script:

```sh
git clone https://github.com/Steven17D/pulsar.git
cd pulsar
./scripts/build.sh
open ~/Applications/Pulsar.app
```

`build.sh` codesigns the bundle ad-hoc with the hardened runtime + Audio
Capture entitlement, places it at `~/Applications/Pulsar.app`, and asks
Spotlight to reindex.

On first launch macOS prompts for **Audio Capture** permission. Approve
via *System Settings → Privacy & Security → Audio Capture → Pulsar*.

To run at login: drag `~/Applications/Pulsar.app` into *System Settings
→ General → Login Items*, or set up a LaunchAgent (see [LaunchAgent](#launchagent)).

## Configuration

Pulsar reads `~/.config/pulsar/config.json`. A default is written on
first run; here is the schema with annotations:

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
  "speed": 1.0,
  "intensity": 1.0,

  "devices": [
    {
      "name": "Office",
      "ip": "192.168.0.192",
      "pixel_count": 237,
      "rgbw": false,
      "brightness": 1.0,
      "enabled": true,
      "segments": [
        { "start": 0,   "length": 119, "reverse": false, "mirror": false },
        { "start": 119, "length": 118, "reverse": true,  "mirror": false }
      ]
    }
  ]
}
```

Most fields are also editable through the menu-bar panel; the JSON file
is the source of truth and is rewritten whenever the panel mutates
something.

### Effects

| id              | Description                                                                |
| --------------- | -------------------------------------------------------------------------- |
| `spectrum`      | Bar-graph EQ split into N segments. Peak-hold dots fall under gravity.      |
| `wavelength`    | Palette gradient scrolls along the strip; brightness from spectrum at x.    |
| `beat_wave`     | Each detected onset spawns a colored wave that traverses the strip.         |
| `ripple`        | Each detected onset spawns a radial ripple from the centre.                 |
| `glitter`       | Palette gradient base + twinkles triggered by high-frequency content.       |
| `solid`         | Whole strip lit by a palette colour, brightness modulated by power.         |
| `test`          | Diagnostic: cycle Red → Green → Blue → White (1 s each).                    |

### Palettes

`sunset`, `ocean`, `forest`, `cyberpunk`, `fire`. Defined as colour
stops in `Sources/Pulsar/Palette.swift`; pull-request your own.

### Segments

When Pulsar boots, it queries each device's `/json/cfg` and learns its
LED buses. Each bus becomes a segment with its own `reverse` + `mirror`
toggles. If a strip on your shelf is wired right-to-left, just flip
`reverse` on that segment from the menu.

If discovery fails (WLED unreachable at boot), Pulsar falls back to a
single segment covering the whole strip. Hit *Refresh* in the device
tab once the controller is back.

## LaunchAgent

For autostart without a Login Items entry, drop this at
`~/Library/LaunchAgents/io.pulsar.audio.plist` and run
`launchctl bootstrap gui/$UID ~/Library/LaunchAgents/io.pulsar.audio.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>io.pulsar.audio</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/YOUR_USER/Applications/Pulsar.app/Contents/MacOS/pulsar</string>
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
  <key>StandardOutPath</key>
  <string>/Users/YOUR_USER/.cache/pulsar.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/YOUR_USER/.cache/pulsar.log</string>
</dict>
</plist>
```

## Architecture

```
+---------------+      +---------------+      +--------------+
| Core Audio    |      |   FFT +       |      |   Mapper     |
| Process Tap   | ===> |   bands       | ===> |   palettes + |
| (background   |      |   (vDSP)      |      |   effects    |
|  thread)      |      |               |      |              |
+---------------+      +---------------+      +------+-------+
                                                     |
                                                     v
                                              +--------------+
                                              |   DDP/UDP    |
                                              |   sender     |
                                              +--------------+
                                                     |
                                                     v
                                              +--------------+
                                              |   WLED       |
                                              |   controller |
                                              +--------------+

  main thread:  SwiftUI MenuBarExtra UI  <----  publishes live frame
```

- The Process Tap callback writes mono-mixed PCM into a lock-protected
  ring buffer. No allocations, no Swift runtime hops in the IOProc.
- A dedicated background `Thread` pulls the latest FFT window every
  `1/fps` seconds, runs vDSP, evaluates the active effect, and emits
  DDP frames per device.
- The UI observes two ObservableObjects: a high-frequency `LiveStore`
  (spectrum + power) and a low-frequency `SettingsStore`
  (config + connection state) so that 60 Hz live updates don't
  invalidate the toggle/slider tree.

## Permissions

- **Audio Capture** (`com.apple.security.device.audio-input`): required
  to attach to the Process Tap. Pulsar calls `TCCAccessRequest`
  internally so the system prompt fires on first launch instead of
  silently delivering zero frames.

That is the only entitlement Pulsar uses. It does not need Microphone,
Accessibility, Screen Recording, or Full Disk Access.

## Troubleshooting

- **`TCC Denied` pill in the panel.** Open System Settings → Privacy &
  Security → Audio Capture, toggle Pulsar on.
- **`Audio Lost`.** Coreaudiod restarted or the default output was
  swapped mid-flight. Pulsar self-respawns within ~2 s; if it stays
  red, try `sudo killall coreaudiod` and relaunch the app.
- **Stripes when sending RGBW.** Your WLED is configured for RGB
  output even though the strip is SK6812 RGBW. Set `"rgbw": false`
  for that device — WLED will auto-derive the W channel from RGB.

## Development

```sh
swift build               # debug
swift build -c release    # release
./scripts/build.sh        # build + install ~/Applications/Pulsar.app
./scripts/package.sh      # build Pulsar.zip for distribution
swift gen-icon.swift      # regenerate AppIcon.icns
```

The Swift module is named `Pulsar`; source lives at `Sources/Pulsar/`.
The wire format and protocol code is in `DDP.swift`; the FFT analyzer in
`FFT.swift`; the Process Tap glue in `Tap.swift` + `CoreAudioUtils.swift`
+ `TCC.swift`.

## Acknowledgments

- [WLED](https://kno.wled.ge/) for the LED-controller firmware and the
  DDP realtime protocol surface.
- [audiotee](https://github.com/insidegui/audiotee) — reference for the
  Process Tap + aggregate-device + tap-attach dance on macOS 14.4+.
- [LedFx](https://www.ledfx.app/) for showing what's possible with
  audio-reactive WLED in the first place.

## License

[MIT](LICENSE).
