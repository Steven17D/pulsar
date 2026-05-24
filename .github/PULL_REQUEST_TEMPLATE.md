## Summary

<!-- One or two sentences: what does this PR change and why? -->

## Test plan

<!--
How did you verify this works? Bullet a short checklist of what you ran
locally. Examples:
  - swift build -c release
  - ./scripts/build.sh && open ~/Applications/Pulsar.app, verified
    Spectrum effect renders on a real WLED device
  - Toggled per-segment reverse on a 2-bus controller, confirmed via
    /json/cfg
-->

- [ ] `swift build` passes
- [ ] `./scripts/build.sh` produces a runnable `~/Applications/Pulsar.app`
- [ ] Manually exercised the affected code path against at least one
      real WLED device (or stated why this is not possible)

## Related issue

<!-- Fixes #NNN, or "n/a" for a chore. -->
