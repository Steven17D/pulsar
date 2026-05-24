# Contributing to Pulsar

Thanks for your interest in Pulsar. This file covers the practical bits
you need to build, change, and ship code against the project.

By contributing you agree that your contributions will be licensed under
the [MIT License](LICENSE), and that you will conduct yourself in line
with the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

- Check the [issue tracker](https://github.com/Steven17D/pulsar/issues)
  and [discussions](https://github.com/Steven17D/pulsar/discussions) for
  existing work.
- For anything larger than a small bug fix or doc tweak, open an issue
  first and propose the change so we can agree on the shape before
  code is written.
- Pulsar is a small, focused tool. Pull requests that pull it toward
  becoming "LedFx but in Swift" will probably be declined; PRs that
  sharpen the existing scope are very welcome.

## Building

Pulsar is a SwiftPM executable. Requirements:

- macOS 14.4 or later (the Process Tap API is the floor).
- Xcode Command Line Tools (`xcode-select --install`).

Common commands:

```sh
swift build                 # debug build of the Pulsar binary
swift build -c release      # release build
./scripts/build.sh          # build + install ~/Applications/Pulsar.app
./scripts/package.sh        # produce Pulsar.zip for distribution
swift gen-icon.swift        # regenerate AppIcon.icns
```

The release `.app` bundle is ad-hoc-signed with the hardened runtime
and the Audio Capture entitlement (`pulsar.entitlements`). On first
launch macOS prompts for **Audio Capture** permission via
*System Settings -> Privacy & Security -> Audio Capture*.

## Tests

Pulsar does not ship a Swift test target yet. Until it does, "tested"
means **manually exercised the affected code path against at least one
real WLED device** and stated which device(s) in the PR description.

If you add a test target, please:

1. Keep it under `Tests/PulsarTests/` so SwiftPM picks it up
   automatically.
2. Wire it into `.github/workflows/ci.yml`.
3. Mention the change in `CHANGELOG.md` under `## [Unreleased]`.

## Code style

- Follow the [Swift API Design Guidelines][sadg]. The standard library
  itself is the reference.
- Use `swift-format`'s defaults if you have it installed locally; CI
  does not currently gate on it, but a future commit will.
- 4-space indentation, LF line endings, UTF-8, final newline. The
  `.editorconfig` at the repo root enforces this in most editors.
- No emoji in code or commit messages.
- Don't add comments that just restate what a well-named identifier
  already conveys.

[sadg]: https://www.swift.org/documentation/api-design-guidelines/

## Commits and pull requests

- Keep the subject line short and imperative ("Add ripple effect", not
  "Added ripple effect" or "Adding ripple effect").
- Put the *why* in the commit body when it isn't obvious from the diff.
- One logical change per PR. Drive-by reformatting belongs in a
  separate PR.
- Fill in the PR template's Summary and Test plan sections; PRs that
  leave them blank will be asked for an edit before review.

## Walkthrough: adding a new effect or palette

Adding an effect touches three places. Adding a palette touches one.

### Adding a palette

1. Open `Sources/Pulsar/Palette.swift`.
2. Add a new entry to the palette table with its colour stops. Stops
   are normalised to `[0, 1]`.
3. The menu-bar panel picks up new palettes automatically because it
   enumerates the table; you do not need to touch the UI.
4. Add a row to the Palettes table in `README.md`.

### Adding an effect

1. Open `Sources/Pulsar/Mapper.swift` (and adjacent files in
   `Sources/Pulsar/` if you need helper types).
2. Implement the effect as a function that takes the analyzer's
   per-frame state (spectrum bands, smoothed power, onsets) and the
   active palette, and returns an array of per-pixel RGB(W) colours.
3. Register the effect in the effects registry so it can be selected
   by id from the config file.
4. Add the id to the Effects table in `README.md` with a one-line
   description.
5. Add a `## [Unreleased]` entry in `CHANGELOG.md` under "Added".
6. In the PR, attach a short clip or a still photo of the effect
   running on real hardware.

If your effect needs new analyzer signals (e.g. a different onset
detector), keep that change in its own PR landed first; the effect PR
is then a smaller diff.

## Security

If you think you've found a security issue, please follow the private
disclosure flow in [SECURITY.md](SECURITY.md). Do not file a public
issue for vulnerabilities.
