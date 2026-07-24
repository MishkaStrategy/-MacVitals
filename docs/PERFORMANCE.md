# Performance

## What CI proves

The pull-request workflow builds, tests, packages and launches the real Release application on hosted Apple Silicon macOS (`macos-15`). The project and command-line gates force `ARCHS=arm64`, and release verification rejects universal or x86_64 executables.

The workflow executes deterministic unit/provider smoke tests and then runs the packaged `MacVitals.app` after a five-second warmup. Process CPU, resident memory, virtual memory, sample continuity and thread count are recorded in CSV and a schema-versioned JSON summary. The process must remain alive and pass broad runaway guardrails.

Synchronous Mach, IOKit and Metal collection remains isolated in a dedicated `SystemSampler` actor, while UI publication remains on `MainActor`.

## Recorded hosted-runner baseline

The last verified Apple Silicon checkpoint before the arm64-only scope migration was Pull Request workflow #200 for version `0.0.200`. It is retained as a regression baseline, not a physical-device performance claim.

| Metric | Hosted arm64 observation |
|---|---:|
| Samples / duration | 22 / 46 s |
| Mean process CPU | 0.405% |
| p95 process CPU | 1.1% |
| Peak RSS | 54.25 MiB |
| RSS growth during measured window | 0.23 MiB |
| Peak threads | 5 |
| Process alive at completion | yes |
| Application runtime log | empty |

A new checkpoint after the arm64-only migration must supersede this baseline before release readiness is claimed.

## CI guardrails

The default CI validator rejects:

- application exit before collection completes;
- fewer than 10 samples or less than 30 seconds of observation;
- severe sample cadence stalls;
- mean process CPU above 75% or p95 above 200%;
- peak RSS above 512 MiB;
- RSS growth above 128 MiB during the warmed measurement window;
- more than 128 threads when the platform exposes thread count.

These thresholds are deliberately broad regression alarms. They are **not** product targets, service-level objectives or claims that all Apple Silicon Macs will match the hosted values.

## What this does not prove

Hosted CI is not an idle-power, wakeup, thermal, battery-runtime or long-duration stability benchmark. It also does not reproduce physical MacBook battery/adapter semantics.

A physical-device benchmark must still record:

- exact Apple Silicon Mac model, CPU/GPU, memory and macOS build;
- power mode and whether the Mac is on battery or external power;
- sampling interval and test duration;
- average, p95 and peak process CPU;
- resident and virtual memory;
- thread count and wakeups;
- Energy Impact or equivalent Instruments evidence;
- behavior while the popover is closed and open;
- sleep/wake recovery;
- provider latency and missing-data behavior;
- at least one multi-hour stability run.

The primary physical target profile remains a MacBook Pro with M1 Pro at the default two-second interval. The app must perform no continuous network activity, subprocess polling or periodic disk writes during normal operation. No physical energy or battery-life claim is considered achieved until corresponding evidence is reviewed and committed.
