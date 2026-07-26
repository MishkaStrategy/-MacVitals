# Physical Apple Silicon runner workflow

The physical workflows are machine-dependent release gates for the existing MacVitals v1 candidate. They do not create a new product path, sign code, merge the pull request, create a tag or publish a release.

## Runner contract

The runner must have these labels:

- `self-hosted`
- `macOS`
- `ARM64`

No custom runner label is required.

The workflows have read-only repository permissions, receive no Apple signing secrets, do not use `sudo`, accept only the owner-created same-repository `feature/macvitals-v1` pull request, check out the exact candidate SHA and refuse a non-arm64 host or candidate. Official checkout and artifact-upload actions are pinned to immutable release commit SHAs.

The runner account must be the active macOS console user. When non-root `launchctl asuser` cannot switch audit sessions, the direct-session workflow uses a narrow compatibility shim:

- normal `launchctl` operations are delegated to `/bin/launchctl`;
- `asuser` execution is permitted only when the requested UID equals the current runner UID;
- a foreign UID is rejected;
- no privilege is added and no `sudo` is used.

## Provision the physical runner

Apple Command Line Tools alone are insufficient: physical validation needs full Xcode because `xcodebuild` and Instruments `xctrace` are supplied by Xcode. Install a Swift 6-capable Xcode under `/Applications/Xcode*.app`.

From an interactive Terminal session run:

```bash
bash scripts/provision_physical_runner.sh --apply
```

The idempotent helper:

- requires native macOS `arm64`;
- finds full Xcode with Swift 6, the macOS SDK and `xctrace`;
- installs `xcodegen` through an existing Homebrew installation when needed;
- selects Xcode with `xcode-select`;
- accepts the Xcode license and completes `xcodebuild -runFirstLaunch`;
- verifies first-launch status, system Git, Xcode, Swift 6, the macOS SDK, `xctrace` and `xcodegen`.

It never downloads Xcode, requests Apple/signing credentials, signs or notarizes code, changes Git history, creates a tag, merges the pull request or publishes a release. `sudo` is used only by this explicit interactive provisioning command for Xcode selection, license acceptance and first-launch components. GitHub Actions validation remains non-mutating and does not use `sudo`.

Read-only inspection:

```bash
bash scripts/provision_physical_runner.sh --check
```

Explicit Xcode selection:

```bash
bash scripts/provision_physical_runner.sh --apply --xcode-app /Applications/Xcode.app
```

## Hardened runner entrypoints

The physical collector must be routed through:

```text
scripts/run_ci_physical_validation_hardened.sh
scripts/run_physical_validation_hardened.py
```

The hardened layer preserves the canonical collection implementation and adds fail-closed contracts:

- indeterminate `pmset` output cannot become a false battery-less result;
- scenario review `pass` requires automated `pass`;
- failed or unrun automated scenarios remain open during finalization;
- `unsupported` closes only `batteryless-desktop`;
- every manual and independent gate requires real `pass`;
- wrapper self-tests verify that the canonical shell route can be patched exactly once and cannot silently fall back to the unhardened harness.

The owner-only `Physical Direct-Session Validation` workflow is the active path for the current runner configuration. The older canonical workflow remains a conservative diagnostic path and must not be treated as release acceptance unless it is routed through the hardened entrypoint.

## Automated evidence

For the exact candidate, the runner performs:

- hardened tooling self-tests, Swift formatting, arm64 unit/provider tests and unsigned package verification;
- a 15-minute popover-closed run;
- a 15-minute idle run matching the observed battery or external-power source;
- battery-less desktop collection only after an explicit reliable no-battery observation, otherwise an honest unsupported/open record;
- a six-hour stability run only while external power remains verifiable, with a watchdog that stops collection if adapter power is lost or cannot be verified;
- before/after power and thermal-state snapshots;
- local-only Instruments collection for Time Profiler, Allocations, Leaks, System Trace and Energy Log when templates are available.

The display may sleep during long runs; `caffeinate` prevents system idle sleep without forcing the display on. The self-hosted job has a 540-minute limit. The long collector deliberately has no step-level timeout because GitHub caps an explicitly configured step timeout at 360 minutes while the collector contains a six-hour scenario; the job-level limit is the controlling bound.

Automated scenarios remain `pending-review`. Missing required scenarios, a failed automated status or missing Instruments traces make the job fail after sanitized evidence is retained. Collection never records a human or independent pass.

## Evidence privacy

Raw runner output is not uploaded before sanitization. The upload gate rejects symlinks, non-regular entries, binary evidence, oversized evidence and remaining home-directory, username, hostname, temporary-workspace or battery-identifier data.

The direct-session hardened privacy gate sanitizes and then independently re-verifies every text evidence file before upload. A successful write alone is not considered proof of privacy.

Raw `.trace` packages can contain machine paths. They remain only on the runner below:

```text
~/MacVitalsPhysicalEvidence/<exact-commit-sha>/<workflow-run-id>/
```

The uploaded artifact contains only redacted logs, exported trace indexes, SHA-256 values and the conservative acceptance record. A reviewer must inspect local traces before changing any Instruments gate to `pass`. Local trace archives should be deleted manually after review and evidence acceptance.

## Gates intentionally left open

The automated workflow cannot honestly complete:

- adapter disconnect/reconnect;
- real sleep/wake interaction;
- the idle scenario for the opposite power source when the runner remains in one state;
- VoiceOver and keyboard navigation;
- EN/RU visual review and real screenshots;
- independent reviewer sign-off;
- Developer ID signing, notarization, stapling or clean-Mac Gatekeeper verification.

Those gates remain open until separately observed and recorded through the hardened acceptance flow. The PR remains Draft; no merge, tag or publication follows automatically.
