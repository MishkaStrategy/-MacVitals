# Physical Apple Silicon runner workflow

The `Physical Apple Silicon Validation` workflow is the machine-dependent release gate for the existing MacVitals v1 candidate. It does not create a new product path, sign code, merge the pull request, create a tag or publish a release.

## Runner contract

The runner must have these labels:

- `self-hosted`
- `macOS`
- `ARM64`

No custom runner label is required.

The workflow has read-only repository permissions, receives no Apple signing secrets, does not use `sudo`, accepts only the owner-created same-repository `feature/macvitals-v1` pull request (or an owner-dispatched post-merge `main` run), checks out the exact candidate SHA and refuses a non-arm64 host or candidate. The runner account must also be the currently logged-in macOS console user with an available `gui/<uid>` launchd domain; physical app and Instruments commands are entered through that GUI bootstrap domain even when the runner listener itself was installed as a service. The required toolchain must already be installed; the workflow does not mutate the physical Mac with Homebrew installs. Official checkout and artifact-upload actions are pinned to immutable release commit SHAs rather than floating tags. Physical candidates use the reserved `0.0.500001+` numeric range so they cannot collide with the normal Pull Request workflow candidate numbering.

## Automated evidence

For the exact candidate, the runner performs:

- tooling self-tests, Swift formatting, arm64 unit/provider tests and unsigned package verification;
- a 15-minute popover-closed run;
- a 15-minute idle run matching the observed battery or external-power source;
- battery-less desktop collection when no battery is present, otherwise an honest `unsupported` record;
- a six-hour stability run only while external power is available, with a 30-second watchdog that stops collection if adapter power is lost or cannot be verified;
- before/after power and thermal-state snapshots;
- local-only Instruments collection for Time Profiler, Allocations, Leaks, System Trace and Energy Log when the templates are available.

The display may sleep during long runs; `caffeinate` prevents system idle sleep without forcing the display on. The self-hosted job has a 540-minute limit. The long collector deliberately has no step-level `timeout-minutes`, because GitHub caps an explicitly configured step timeout at 360 minutes while this collector contains a six-hour stability scenario; the job-level limit is the controlling upper bound. Automated physical scenarios remain `pending-review`. Missing required scenarios or Instruments traces make the job fail after sanitized evidence is retained. The workflow never records a human or independent `pass`.

## Evidence privacy

Raw runner output is never printed or uploaded before sanitization. The upload gate rejects symlinks, non-regular entries, binary evidence, oversized evidence and remaining home-directory, username, hostname, temporary-workspace or battery-identifier data. Evidence artifacts are uploaded only after the explicit privacy step succeeds. If that upload fails after a long run, the already-sanitized evidence is retained locally beside the raw trace run under a `sanitized-upload-fallback` directory instead of being lost during workspace cleanup.

Raw `.trace` packages can contain machine paths. They are therefore retained only on the runner below:

```text
~/MacVitalsPhysicalEvidence/<exact-commit-sha>/<workflow-run-id>/
```

The uploaded artifact contains only redacted logs, exported trace indexes, SHA-256 values and the conservative acceptance record. A reviewer must inspect the local traces before changing any Instruments gate to `pass`. Local trace archives should be deleted manually after review and evidence acceptance.

## Gates intentionally left open

The workflow cannot honestly automate:

- adapter disconnect/reconnect;
- real sleep/wake interaction;
- the idle scenario for the opposite power source when the runner remains in one power state;
- VoiceOver and keyboard navigation;
- EN/RU visual review and screenshots;
- independent reviewer sign-off;
- Developer ID signing, notarization, stapling or clean-Mac Gatekeeper verification.

Those gates remain open until separately observed and recorded.
