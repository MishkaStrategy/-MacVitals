# Physical Apple Silicon runner workflow

The `Physical Apple Silicon Validation` workflow is the machine-dependent release gate for the existing MacVitals v1 candidate. It does not create a new product path, sign code, merge the pull request, create a tag or publish a release.

## Runner contract

The runner must have these labels:

- `self-hosted`
- `macOS`
- `ARM64`

No custom runner label is required.

The workflow has read-only repository permissions, receives no Apple signing secrets, does not use `sudo`, accepts only the owner-created same-repository `feature/macvitals-v1` pull request (or an owner-dispatched post-merge `main` run), checks out the exact candidate SHA and refuses a non-arm64 host or candidate. The required build and Instruments toolchain must already be installed before validation. Official checkout and artifact-upload actions are pinned to immutable release commit SHAs rather than floating tags. Physical candidates use the reserved `0.0.500001+` numeric range so they cannot collide with normal Pull Request workflow candidate numbering.

## Provision the physical runner

Apple Command Line Tools alone are insufficient: physical validation needs a full Xcode installation because `xcodebuild` and Instruments `xctrace` are supplied by Xcode. Install a Swift 6-capable Xcode from the Mac App Store or Apple Developer downloads and place it under `/Applications/Xcode*.app`.

After Xcode is present, run this command from a checkout of `feature/macvitals-v1` in an interactive Terminal session:

```bash
bash scripts/provision_physical_runner.sh --apply
```

The helper is idempotent and performs only runner provisioning:

- requires native macOS `arm64`;
- finds a full Xcode with Swift 6, the macOS SDK and `xctrace`;
- installs `xcodegen` through an already installed Homebrew when needed;
- selects that Xcode with `xcode-select`;
- accepts the Xcode license and completes `xcodebuild -runFirstLaunch`;
- verifies Xcode, Swift 6, the macOS SDK, `xctrace` and `xcodegen`.

It never downloads Xcode, requests Apple/signing credentials, signs or notarizes code, changes Git history, creates a tag, merges the pull request or publishes a release. `sudo` is used only by this explicit interactive provisioning command for `xcode-select`, license acceptance and first-launch components. The GitHub Actions validation workflow itself remains non-mutating and does not use `sudo`.

A read-only inspection is available with:

```bash
bash scripts/provision_physical_runner.sh --check
```

When several Xcode applications are installed, select one explicitly:

```bash
bash scripts/provision_physical_runner.sh --apply --xcode-app /Applications/Xcode.app
```

After provisioning succeeds, any new synchronize event on the Draft PR triggers the exact-head physical workflow. A documentation-only commit is sufficient; no merge, tag or release action is needed.

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
