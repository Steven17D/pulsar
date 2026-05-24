# Changelog

All notable changes to Pulsar are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.1] - 2026-05-24

### Added

- Per-slider audio reactivity for Brightness, Speed, Intensity. Each
  slider has a waveform-pill toggle and a gear popover to pick which
  aspect drives it: Power, Bass, Treble, or Beat Onset.
- Plasma effect: phase rate scales with audio power via sqrt-compressed
  RMS and an intensity-controlled gain.
- Rainbow effect: uses HSV spectrum directly, overrides palette so the
  rainbow is always literal hue.
- Seamless palette traversal across Breathe, Comet, Solid, Wavelength
  via triangle-fold (0→1→0) so palette endpoints no longer jump.
- Initial public source drop of Pulsar: audio-reactive WLED controller
  for macOS, built on the Core Audio Process Tap API (macOS 14.4+).
- 5 reactive effects: Spectrum Bars, Wavelength, Beat Wave, Ripple,
  Glitter, plus Solid ambient mode and a Test diagnostic.
- 5 palettes: Sunset, Ocean, Forest, Cyberpunk, Fire.
- Per-strip on/off, per-strip brightness, segment-level reverse and
  in-segment mirror.
- Auto-discovery of WLED segments via `/json/cfg`.
- SwiftUI menu-bar panel with live spectrum + power meter.
- Self-healing audio engine: respawns on `coreaudiod` restart and
  default-output device swap.
- DDP/UDP frame sender at 60 Hz, RGB and RGBW modes.
- `scripts/build.sh` and `scripts/package.sh` for local install and
  distributable `Pulsar.zip` builds.
- SwiftPM unit test target for pure logic checks, starting with config
  sanitization coverage.
- Public-readiness docs for screenshots, contribution flow, security
  reporting, and repository review.

### Fixed

- Malformed config values are sanitized before they can crash FFT setup,
  render timing, segment serialization, or brightness math.
- Legacy effect migration now maps old effect ids only to available
  renderers.
