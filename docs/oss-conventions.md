# OSS conventions for Pulsar

A short, opinionated memo distilled from reading six concrete public repos
before Pulsar goes public. Cited claims are anchored to specific repos so
the reasoning is auditable later.

References used:

- `openai/codex` — actively curated multi-package Rust/TS repo
- `sst/opencode` — TypeScript-heavy modern repo with release automation
- `ghostty-org/ghostty` — native macOS+Linux app, polished public repo
- `sst/cmux` — *not found at the expected slug; treated as no-signal*
- `niki-on-github/kaku` — *not found at the expected slug; treated as no-signal*
- `gnachman/iTerm2` — venerable macOS app, signed builds, donations enabled

## README conventions

- **Badge row** sits immediately after the H1 title. Standard set seen on
  active projects: CI status, license, latest release, supported platforms.
  Use shields.io URLs derived from the workflow file name and the repo
  slug. Even when a badge would render "none" (e.g. no releases yet) the
  badge is still emitted; the convention is "the row appears the day the
  README first ships, content fills in later".
- **Hero / TL;DR paragraph** — one or two sentences immediately under the
  badges that answer "what is this and why would I run it". Ghostty does
  this; codex does this; opencode does this.
- **Feature list** — short bulleted list, not a wall of prose. Pulsar's
  README already has this.
- **Install / Quickstart** — should be the first runnable block. Pulsar
  already has it. No changes proposed.
- **Screenshots section** — small dedicated section linking to a
  `docs/screenshots/` directory rather than embedding many images inline.
  iTerm2 and ghostty both follow this pattern. The directory is created
  even when empty so the link is not broken on the day the repo flips
  public.
- **Contributing pointer** — short paragraph or "See CONTRIBUTING.md"
  cross-link. Don't duplicate CONTRIBUTING content into the README;
  every reference repo studied keeps them strictly separated.
- **Security callout** — one-liner "found a vulnerability? see
  SECURITY.md". codex does this implicitly by virtue of `SECURITY.md`
  being at repo root; ghostty links to it inline.
- **License footer** — last line, single link to the LICENSE file.

## `.github/` directory expectations

The repos studied converge on the following set:

- `ISSUE_TEMPLATE/` — YAML form schema (`name`, `description`, `body:`),
  not the older Markdown frontmatter style. codex, opencode, and ghostty
  are all on YAML forms.
- `ISSUE_TEMPLATE/config.yml` — universally present, sets
  `blank_issues_enabled: false` and adds `contact_links` pointing at
  Discussions or the docs. ghostty's `config.yml` is the cleanest model.
- `PULL_REQUEST_TEMPLATE.md` — a single Markdown file at `.github/`
  root. opencode's is the most usable example: short Summary, Test plan,
  Checklist.
- `CODEOWNERS` — even when there's a single maintainer, the file is
  present so future onboarding doesn't require remembering the syntax.
  ghostty splits ownership by subsystem (font, GTK, macOS, renderer);
  for Pulsar, a single catch-all `* @Steven17D` is enough.
- `FUNDING.yml` — present on iTerm2 (Patreon, GitHub Sponsors, PayPal).
  Best practice for a fresh public repo: commit the file with everything
  commented out so enabling sponsorship later is a one-line flip.
- `dependabot.yml` — universally present. codex configures six
  ecosystems; ghostty configures just `github-actions`. The latter is
  the right baseline for Pulsar since SwiftPM has zero deps today.
- `workflows/` — CI on push/PR, plus a release workflow gated by a tag
  push pattern (`v*.*.*`). ghostty has separate `release-tag.yml` (full
  release) and `release-tip.yml` (nightly); for a first public release
  one workflow on `v*.*.*` is sufficient.

## Release pipeline patterns for macOS apps

Studied: ghostty's `release-tag.yml`, iTerm2's signing scripts.

- **Trigger** — push of a tag matching `v*.*.*`. Manual `workflow_dispatch`
  is offered as a backup. Pulsar adopts both.
- **Build job** — runs on `macos-15` (or whatever the latest stable
  hosted runner is). The repo's existing build script is the build step;
  the workflow doesn't re-derive build commands.
- **Signing** — ghostty uses Apple Developer ID + notarytool; iTerm2
  notarizes too. For Pulsar today, ad-hoc signing is acceptable because
  no Apple Developer ID is provisioned. The workflow signs ad-hoc and
  leaves a TODO comment pointing at Apple's notarization docs for the
  day a Developer ID is added (secrets `APPLE_DEVELOPER_ID_APPLICATION`,
  `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`).
- **Artifact** — `.zip` of the `.app` bundle. ghostty additionally ships
  a `.dmg` and an appcast for Sparkle; not in scope for Pulsar v0.
- **Release** — the workflow creates a **draft** GitHub Release with the
  zip attached and lets a human review + publish. ghostty does the same
  thing.
- **No third-party signing actions** — both ghostty and iTerm2 invoke
  `codesign`, `xcrun notarytool`, and `ditto` directly. Avoid the wider
  marketplace of "macOS notarize" actions.

## Security policy norms

- File lives at repo root as `SECURITY.md`.
- Section structure converging across repos: "Supported Versions" (often
  trivial for a single-track app), "Reporting a Vulnerability", "What to
  expect".
- **Preferred channel** — GitHub Security Advisories (private). Several
  projects (codex routes to Bugcrowd) link out instead. For Pulsar the
  right starting point is GHSA: it's free, private, and doesn't require
  a personal email to be published. A placeholder email can be added
  later if the maintainer wants one.
- **Attack-surface call-out** — most security policies omit this. Apps
  that touch system audio + UDP sockets benefit from an explicit one:
  reduces wasted reports from researchers fuzzing the wrong surface.

## Code of Conduct norms

- Universally adopted: **Contributor Covenant 2.1** verbatim. The only
  per-project edits are the contact line at the bottom.
- For private-then-public flips: point the contact line at the
  GitHub user handle and/or GitHub Discussions rather than a personal
  email. Real email can be added once the maintainer wants the inbox.

## Brew / Cask publishing patterns

Not implemented in Pulsar v0 but worth documenting for the day it
matters:

- macOS GUI apps publish via **Homebrew Cask**, not Homebrew core.
- The cask formula points at the GitHub Release zip artifact (the same
  one Pulsar's release workflow already produces).
- Two routes: (a) submit a cask PR to `homebrew/homebrew-cask`
  (preferred for established projects), (b) maintain a personal tap at
  `Steven17D/homebrew-pulsar` with a single `Casks/pulsar.rb` (lower
  friction for first release). `sst`-family repos use personal taps for
  fast iteration before upstreaming.
- The cask requires SHA256 of the zip; the release workflow's draft
  release page exposes that hash, so updating the cask is a copy-paste
  job per release.
