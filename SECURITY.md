# Security Policy

## Supported versions

Pulsar is on a single release track. Security fixes land on `main` and
are included in the next tagged release. There are no long-term support
branches.

| Version | Supported |
| ------- | --------- |
| `main`  | yes       |
| latest tagged release | yes |
| older tags | no       |

## Reporting a vulnerability

Please report security issues **privately** so a fix can ship before
the issue is public. Two acceptable channels:

1. **Preferred:** open a [GitHub Security Advisory](https://github.com/Steven17D/pulsar/security/advisories/new)
   on this repository. This keeps the report private until the
   maintainer publishes it.
2. Direct message [@Steven17D on GitHub](https://github.com/Steven17D)
   with a short description and a way to follow up.

Do **not** file a public issue, open a PR with proof-of-concept code,
or post details on Discussions until the issue is resolved.

## What to include

Where possible:

- A description of the issue and the impact you believe it has.
- A minimal reproduction (config snippet, command line, WLED firmware
  version, macOS version).
- Whether you would like to be credited in the release notes.

## What to expect

- An acknowledgment within a few working days.
- A status update at least once a week while the issue is being worked
  on.
- A coordinated disclosure date once a fix is in hand. Credit in the
  release notes if you would like it.

## Out of scope

The following are not considered vulnerabilities:

- Anything that requires an attacker who already has physical or
  console access to the user's Mac.
- Resource exhaustion via malformed local config files. Pulsar's
  config is a user-owned file; trust is rooted at the file system.
- Issues in third-party software Pulsar talks to (WLED firmware,
  macOS frameworks). Please report those upstream.

## Attack surface (for triage)

For researchers deciding where to look:

- **Audio Capture entitlement** (`com.apple.security.device.audio-input`):
  Pulsar reads the system audio output via the Process Tap API. It
  does not record to disk and does not transmit audio off the host.
- **Outbound UDP to LAN**: Pulsar sends DDP frames (UDP/4048) to
  WLED controllers listed in the config. It does not bind any
  inbound listening socket.
- **Outbound HTTP to LAN**: Pulsar queries `/json/cfg` on each
  configured WLED device at startup and on user-triggered refresh.
- **Local config file**: read/write to `~/.config/pulsar/config.json`.
  Nothing outside `~/.config/pulsar/` is written.

Bugs anywhere outside that surface are interesting but most likely
not security-impacting.
