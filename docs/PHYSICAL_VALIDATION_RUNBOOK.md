# Physical Apple Silicon Validation Runbook

This runbook executes the remaining machine-dependent MacVitals checks without changing the supported scope or claiming results that were not observed.

The harness is intended for native Apple Silicon only. Intel and universal validation are outside the project scope.

## Safety and evidence contract

The harness:

- accepts only an arm64 candidate that passes `scripts/verify_release.sh`;
- verifies that the tested `MacVitals.app` executable matches the verified candidate ZIP byte for byte;
- records the hardware model, memory size, logical CPU count and macOS version without recording a serial number, Apple ID, username or home path;
- records parsed `pmset -g batt` power state without retaining the raw battery identifier;
- pins runtime evidence to the exact executable, PID, UID and process start identity;
- stores every run in a new directory below `physical-validation-results/`;
- leaves manual, Instruments, independent-review and signing gates as `not-tested` until a reviewer explicitly records a result;
- fails its privacy scan if generated text evidence contains `/Users/<name>` or `/home/<name>`.

The harness does not use `sudo`, does not modify system power settings and does not publish evidence automatically.

## Prepare the exact candidate

1. Download the intended `MacVitals-<version>-arm64-unsigned` workflow artifact.
2. Extract its five files into the repository `dist/` directory:
   - `MacVitals-<version>.zip`;
   - `MacVitals-<version>.dmg`;
   - `BUILD_STATUS.txt`;
   - `BUILD_MANIFEST.json`;
   - `SHA256SUMS.txt`.
3. Install or extract that exact build as `/Applications/MacVitals.app`.
4. From the repository root run:

```bash
python3 scripts/run_physical_validation.py prepare \
  --version <version> \
  --app /Applications/MacVitals.app
```

Preparation verifies checksums, ZIP/DMG parity, metadata, signing/notarization classification, exact arm64 architecture and executable identity. It then creates:

```text
physical-validation-results/session-<UTC>-<PID>/
```

Use the exact session path printed by the command in every following step.

## Primary MacBook scenarios

### Battery idle

Disconnect external power before starting and keep the popover closed:

```bash
python3 scripts/run_physical_validation.py run \
  --session physical-validation-results/session-<UTC>-<PID> \
  --scenario battery-idle \
  --app /Applications/MacVitals.app \
  --duration 900 \
  --interval 2
```

The automated portion fails if the machine does not remain on battery power.

### External-power idle

Connect the normal Apple-recommended adapter and keep the popover closed:

```bash
python3 scripts/run_physical_validation.py run \
  --session physical-validation-results/session-<UTC>-<PID> \
  --scenario external-power-idle \
  --app /Applications/MacVitals.app \
  --duration 900 \
  --interval 2
```

### Adapter disconnect and reconnect

Start on external power. During the five-minute run, disconnect the adapter after approximately one minute and reconnect it after another minute:

```bash
python3 scripts/run_physical_validation.py run \
  --session physical-validation-results/session-<UTC>-<PID> \
  --scenario adapter-transition \
  --app /Applications/MacVitals.app \
  --duration 300 \
  --interval 2
```

The harness samples parsed power state throughout the run and fails unless both battery and external-power states are captured.

Repeat this scenario for each available connection class, such as MagSafe, direct USB-C, dock/display power delivery and a lower-wattage adapter. Add the connection type as a note, never a serial number.

### Sleep and wake

Start the run, wait approximately one minute, put the Mac to sleep for at least thirty seconds, wake it and let the command finish:

```bash
python3 scripts/run_physical_validation.py run \
  --session physical-validation-results/session-<UTC>-<PID> \
  --scenario sleep-wake \
  --app /Applications/MacVitals.app \
  --duration 300 \
  --interval 2
```

The automated check requires a plausible suspended wall-clock interval and stable process identity. Review the application after wake to confirm fresh samples, correct power state and no stale alert storm.

## UI-state and workload scenarios

Run the following separately so each evidence directory has one clear workload.

### Popover closed

```bash
python3 scripts/run_physical_validation.py run \
  --session physical-validation-results/session-<UTC>-<PID> \
  --scenario popover-closed \
  --app /Applications/MacVitals.app \
  --duration 900 \
  --interval 2
```

### Popover open

Open the MacVitals popover before starting:

```bash
python3 scripts/run_physical_validation.py run \
  --session physical-validation-results/session-<UTC>-<PID> \
  --scenario popover-open \
  --app /Applications/MacVitals.app \
  --duration 900 \
  --interval 2
```

### High-frequency sampling

Set MacVitals to its 0.5-second interval before starting:

```bash
python3 scripts/run_physical_validation.py run \
  --session physical-validation-results/session-<UTC>-<PID> \
  --scenario high-frequency \
  --app /Applications/MacVitals.app \
  --duration 900 \
  --interval 0.5
```

The harness rejects a `high-frequency` run whose evidence interval is above 0.5 seconds.

### Controlled stress

Start a documented, bounded CPU/memory workload in another terminal, then run:

```bash
python3 scripts/run_physical_validation.py run \
  --session physical-validation-results/session-<UTC>-<PID> \
  --scenario stress \
  --app /Applications/MacVitals.app \
  --duration 900 \
  --interval 2 \
  --note "Describe the controlled workload without paths or personal data"
```

Do not reproduce critical memory pressure when it would risk data loss.

### Six-hour stability

Keep the intended release settings unchanged throughout the run:

```bash
python3 scripts/run_physical_validation.py run \
  --session physical-validation-results/session-<UTC>-<PID> \
  --scenario stability-six-hour \
  --app /Applications/MacVitals.app \
  --duration 21600 \
  --interval 2
```

The harness rejects a shorter run under this scenario name.

## Battery-less Apple Silicon desktop

On an Apple Silicon desktop, run:

```bash
python3 scripts/run_physical_validation.py run \
  --session physical-validation-results/session-<UTC>-<PID> \
  --scenario batteryless-desktop \
  --app /Applications/MacVitals.app \
  --duration 900 \
  --interval 2
```

The automated portion fails if `pmset` reports a battery. On a MacBook, record this scenario as unsupported rather than pretending it ran:

```bash
python3 scripts/run_physical_validation.py review \
  --session physical-validation-results/session-<UTC>-<PID> \
  --scenario batteryless-desktop \
  --status unsupported \
  --note "Requires a separate Apple Silicon desktop"
```

## Review scenario evidence

Automated success means only that the collector, identity, timing, privacy and scenario-specific machine invariants passed. It does not replace human review of sensor semantics or UI behavior.

After inspecting a scenario, record the review decision:

```bash
python3 scripts/run_physical_validation.py review \
  --session physical-validation-results/session-<UTC>-<PID> \
  --scenario adapter-transition \
  --status pass \
  --note "No stale values or repeated alert storm observed"
```

Use `fail`, `not-tested` or `unsupported` honestly when applicable.

## Manual and Instruments gates

Record a manual gate only after the corresponding evidence has been reviewed. Example:

```bash
python3 scripts/run_physical_validation.py manual \
  --session physical-validation-results/session-<UTC>-<PID> \
  --gate voiceOver \
  --status pass \
  --note "All Preferences tabs and menu-bar controls reviewed"
```

Supported manual gate names are visible with:

```bash
python3 scripts/run_physical_validation.py manual --help
```

Instruments traces remain separate binary evidence. Record only their reviewed result and redacted filename; do not claim the harness itself measured wakeups, Energy Impact, allocations or leaks.

The authoring assistant must not mark `independentReviewer` as passed. That gate requires a separate reviewer.

Signing, notarization, stapling and Gatekeeper gates must remain `not-tested` until the final signed artifacts exist.

## Finalize the record

Generate the conservative Markdown acceptance report:

```bash
python3 scripts/run_physical_validation.py finalize \
  --session physical-validation-results/session-<UTC>-<PID>
```

Exit status `2` means open or unreviewed gates remain. This is intentional and must not be bypassed by deleting scenarios or weakening the acceptance rules.

A complete session contains:

- copied candidate manifest, status and checksum metadata;
- redacted host and tested-app identity;
- per-scenario runtime CSV/JSON;
- parsed power-state timeline;
- automated failures and review decisions;
- `acceptance.json`;
- `ACCEPTANCE.md`;
- an explicit list of every still-open release gate.

Do not commit unreviewed physical evidence automatically. First inspect it for privacy, then attach or commit only the redacted acceptance record and evidence approved by the project reviewer.
