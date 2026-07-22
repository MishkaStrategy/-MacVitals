# Physical Hardware Validation

Hosted macOS CI proves compilation, deterministic logic, provider smoke behavior and packaging. It does not prove MacBook battery semantics, real adapter behavior, Intel compatibility, long-duration stability or process energy impact. This protocol defines the remaining physical validation evidence.

## Evidence rules

- Record only observations produced by the exact tested build.
- Never infer measured wall/input power from adapter rated power.
- Never convert a missing sensor into zero.
- Preserve availability, source, timestamp and confidence fields in exported diagnostics.
- Do not record serial numbers, Apple ID, usernames, home paths or user documents.
- Mark a scenario `not tested`, `unsupported`, `unavailable` or `failed`; do not silently omit it.
- Attach the package `BUILD_MANIFEST.json`, `BUILD_STATUS.txt` and `SHA256SUMS.txt` to every validation set.

## Required hardware matrix

At minimum, validate:

| Class | Minimum scenario |
|---|---|
| Apple Silicon laptop | M1 Pro MacBook Pro, internal display, battery and USB-C/MagSafe adapters |
| Newer Apple Silicon laptop | At least one M2/M3/M4-family MacBook when available |
| Intel laptop | One supported Intel MacBook or an explicit decision to drop the Intel claim |
| Desktop | One battery-less Mac to confirm graceful unsupported battery behavior |

For every machine record only:

- marketing model name;
- architecture;
- memory size;
- macOS version and build;
- MacVitals version/build and Git commit from `BUILD_MANIFEST.json`;
- adapter marketing wattage and connection type without serial number.

## Installation and launch

1. Verify every SHA-256 entry.
2. Confirm `BUILD_STATUS.txt` accurately describes signing and notarization.
3. Install from the DMG into Applications.
4. Confirm menu-bar-only launch with `LSUIElement` behavior.
5. Open Preferences with Command–Comma.
6. Validate English and Russian interfaces.
7. Enable and disable Launch at Login; record whether macOS requires approval.
8. Restart the user session and confirm the actual launch state.

## Provider scenarios

### CPU

- idle desktop;
- sustained single-thread load;
- sustained multi-core load;
- sleep and wake while collection is active;
- check that the first post-wake sample is treated as a new baseline.

### Memory

- normal pressure;
- warning pressure induced by a controlled workload;
- critical pressure only when safe to reproduce;
- confirm percentage and native pressure remain separate signals;
- confirm pressure recovery clears the active alert state.

### Battery

- discharging on battery;
- charging below 80%;
- connected near full charge;
- time-to-empty/time-to-full unavailable cases;
- plausible signed battery watts;
- cycle count, capacities, health and temperature when available;
- no false `0%` when capacity inputs are missing.

### Adapter

- no adapter;
- low-wattage USB-C adapter;
- Apple-recommended adapter;
- higher-rated USB-C or MagSafe adapter;
- disconnect/reconnect transitions;
- dock or display power delivery when available;
- confirm rated/negotiated power is never labeled measured input power.

### Charger sufficiency

For each adapter/load combination:

1. Start below full battery charge.
2. Keep the workload stable longer than the confirmation window.
3. Record battery watts, power status, confidence and explanation.
4. Repeat at least three times.
5. Confirm brief transients do not produce repeated notifications.
6. Confirm sustained battery discharge while externally powered reaches `insufficient` only after the configured duration/sample count.
7. Confirm reconnecting power resets the evidence window.

### GPU

- confirm Metal identity/capability data;
- confirm whole-system utilization remains explicitly unavailable unless a trustworthy provider is later implemented;
- confirm the support bundle removes the stable Metal registry identifier.

## Runtime performance collection

Launch the packaged app, leave the popover closed, and run:

```bash
bash scripts/collect_runtime_metrics.sh 900 2
```

Repeat with:

- popover closed at idle;
- popover open;
- 0.5-second update interval;
- default 2-second interval;
- CPU/memory stress workload;
- sleep/wake cycle;
- six-hour stability run when feasible.

The script creates CSV samples and a JSON summary without administrator privileges. It measures process CPU, RSS, VSZ and thread count. It does not replace Instruments measurements of wakeups or Energy Impact.

## Instruments pass

Capture separate Instruments evidence for:

- Time Profiler;
- Allocations/Leaks;
- System Trace or an equivalent wakeup view;
- Energy Log when supported by the tested macOS/Xcode combination.

Record average, p95 and peak values only with the trace duration, workload and hardware context. Do not publish universal performance claims from one machine.

## Alerts and permission states

- alerts disabled: no notification-system request;
- first enable: one permission flow only;
- denied permission: actionable Preferences message;
- threshold slider changes: no cooldown reset or duplicate alert;
- disable/re-enable: policy reset is intentional;
- low battery alert only while discharging;
- memory pressure alert can precede percentage threshold;
- power alert requires the confidence threshold.

## Diagnostics and privacy

Export a support bundle for each major scenario and verify:

- schema version and app/build metadata;
- provider availability/source/timestamps;
- sampling health and overrun state;
- no username or home path;
- no serial number;
- no Apple ID or documents;
- no network data;
- no stable GPU registry identifier.

## Acceptance record

For each machine produce a signed-off record containing:

- pass/fail/not-tested table;
- links to redacted support bundles;
- runtime CSV/JSON summaries;
- Instruments trace filenames and summarized findings;
- screenshots in both languages;
- known deviations and release impact;
- tester and date.

The project must remain draft until required scenarios pass or the supported scope is explicitly narrowed in documentation and metadata.
