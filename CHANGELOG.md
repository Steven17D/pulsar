# Changelog

All notable changes to Pulsar are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
