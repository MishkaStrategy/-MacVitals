# Physical Apple Silicon Validation Runbook

This runbook executes machine-dependent MacVitals checks without changing the supported scope or claiming results that were not observed.

The harness is intended for native Apple Silicon (`arm64`) only. Intel and universal validation are outside the MacVitals v1 scope.

## Mandatory hardened entrypoint

Use only:

```text
scripts/run_physical_validation_hardened.py
```

Do not use the underlying compatibility module directly for release acceptance. The hardened entrypoint preserves the canonical collection logic and adds fail-closed power parsing and acceptance rules.

The hardened rules guarantee that:

- empty, failed or indeterminate `pmset` output is not interpreted as a battery-less Mac;
- a scenario cannot receive review `pass` until its automated status is `pass`;
- an automated `fail` or `not-run` remains open during finalization;
- `unsupported` is accepted only for the hardware-specific `batteryless-desktop` scenario;
- manual, Instruments, independent-review, signing, notarization and Gatekeeper gates require a real explicit `pass` to close.

## Safety and evidence contract

The harness:

- accepts only an arm64 candidate that passes `scripts/verify_release.sh`;
- verifies that the tested `MacVitals.app` executable matches the verified candidate ZIP byte for byte;
- records the hardware model, memory size, logical CPU count and macOS version without recording a serial number, Apple ID, username or home path;
- records parsed `pmset -g batt` power state without retaining the raw battery identifier;
- pins runtime evidence to the exact executable, PID, UID and process start identity;
- stores every run in a new directory below `physical-validation-results/`;
- leaves human, Instruments, independent-review and signed-release gates open until real evidence is reviewed;
- fails its privacy scan if generated text evidence contains a user home path.

The harness does not use `sudo`, does not modify system power settings and does not publish evidence automatically.

## Prepare the exact candidate

The preferred path is the resource-limited outer-artifact staging flow documented in [`PHYSICAL_VALIDATION_GUIDED.md`](PHYSICAL_VALIDATION_GUIDED.md).

For a manually installed exact candidate:

1. Download the intended `MacVitals-<version>-arm64-unsigned` workflow artifact.
2. Extract its five files into `dist/`:
   - `MacVitals-<version>.zip`;
   - `MacVitals-<version>.dmg`;
   - `BUILD_STATUS.txt`;
   - `BUILD_MANIFEST.json`;
   - `SHA256SUMS.txt`.
3. Install or extract that exact build as `/Applications/MacVitals.app`.
4. Run:

```bash
python3 scripts/run_physical_validation_hardened.py prepare \
  --version <version> \
  --app /Applications/MacVitals.app
```

Preparation verifies checksums, ZIP/DMG parity, metadata, signing/notarization classification, exact arm64 architecture and executable identity. It creates a new session:

```text
physical-validation-results/session-<UTC>-<PID>/
```

Use the exact printed session path in every following command.

## Run a scenario

Use this template:

```bash
python3 scripts/run_physical_validation_hardened.py run \
  --session physical-validation-results/session-<UTC>-<PID> \
  --scenario <scenario> \
  --app /Applications/MacVitals.app \
  --duration <seconds> \
  --interval <seconds> \
  --review-status pending-review
```

Approved profiles:

| Scenario | Duration | Interval | Required physical state/action |
|---|---:|---:|---|
| `battery-idle` | 900 s | 2 s | Disconnect external power and remain on battery. |
| `external-power-idle` | 900 s | 2 s | Connect the intended adapter and keep it connected. |
| `adapter-transition` | 300 s | 2 s | Start on AC, disconnect, then reconnect during the run. |
| `sleep-wake` | 300 s | 2 s | Sleep long enough to create a visible gap, then wake. |
| `popover-closed` | 900 s | 2 s | Keep the popover closed. |
| `popover-open` | 900 s | 2 s | Keep the popover open. |
| `high-frequency` | 900 s | 0.5 s | Set the application interval to 0.5 seconds. |
| `stress` | 900 s | 2 s | Run a documented bounded CPU/memory workload. |
| `stability-six-hour` | 21600 s | 2 s | Keep release settings unchanged on verifiable external power. |
| `batteryless-desktop` | 900 s | 2 s | Run only on an Apple Silicon desktop with no battery. |

Do not reproduce critical memory pressure when it would risk data loss. Notes must not contain personal paths, serial numbers or unrelated user data.

## Scenario-specific automated requirements

- `battery-idle` must start and remain on battery.
- `external-power-idle` must start and remain on external power.
- `adapter-transition` must capture both battery and external-power states.
- `sleep-wake` must contain a plausible suspended wall-clock interval while process identity remains controlled.
- `high-frequency` rejects an interval above 0.5 seconds.
- `stability-six-hour` rejects a duration below 21,600 seconds.
- `batteryless-desktop` requires an explicit reliable `batteryPresent=false`; unknown power output cannot satisfy it.

Repeat `adapter-transition` for each available connection class, such as MagSafe, direct USB-C, dock/display power delivery and a lower-wattage adapter. Record only the connection class, never a serial number.

## Review scenario evidence

Automated success confirms collector, identity, timing, privacy and scenario-specific machine invariants only. It does not replace human review of sensor semantics or UI behavior.

After reviewing a scenario that has automated `pass`, record the decision:

```bash
python3 scripts/run_physical_validation_hardened.py review \
  --session physical-validation-results/session-<UTC>-<PID> \
  --scenario adapter-transition \
  --status pass \
  --note "No stale values or repeated alert storm observed"
```

The command rejects `pass` when automated evidence has not passed.

Use `fail` or `not-tested` honestly. `unsupported` is accepted only for `batteryless-desktop`, for example on a MacBook:

```bash
python3 scripts/run_physical_validation_hardened.py review \
  --session physical-validation-results/session-<UTC>-<PID> \
  --scenario batteryless-desktop \
  --status unsupported \
  --note "Requires a separate Apple Silicon desktop"
```

## Manual and Instruments gates

Record a manual gate only after the corresponding evidence has genuinely been reviewed:

```bash
python3 scripts/run_physical_validation_hardened.py manual \
  --session physical-validation-results/session-<UTC>-<PID> \
  --gate voiceOver \
  --status pass \
  --note "All Preferences tabs and menu-bar controls reviewed"
```

View supported names with:

```bash
python3 scripts/run_physical_validation_hardened.py manual --help
```

Manual gates reject `unsupported`. Leave a gate `not-tested` or `pending-review` until the real evidence exists.

Instruments traces remain separate local binary evidence. Record only the reviewed result and redacted reference; collection alone is not a pass.

The authoring assistant must not mark `independentReviewer` as passed. That requires a separate real reviewer. Developer ID signing, notarization, stapling and clean-Mac Gatekeeper must remain open until separately authorized signed artifacts exist and are genuinely tested.

## Finalize the record

```bash
python3 scripts/run_physical_validation_hardened.py finalize \
  --session physical-validation-results/session-<UTC>-<PID>
```

Exit status `2` means required automated evidence, human review or manual gates remain open. Finalization evaluates both `automatedStatus` and `reviewStatus`; editing only the review state cannot hide a failed or unrun scenario.

A complete session contains:

- copied candidate manifest, status and checksum metadata;
- redacted host and tested-app identity;
- per-scenario runtime CSV/JSON;
- parsed power-state timeline;
- automated failures and review decisions;
- `acceptance.json`;
- `ACCEPTANCE.md`;
- an explicit list of every still-open release gate.

Do not commit unreviewed physical evidence automatically. Inspect it for privacy first, keep raw Instruments traces local, and attach only the redacted records approved for review.
