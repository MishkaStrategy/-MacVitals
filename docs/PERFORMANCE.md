# Performance

## What CI proves

The pull-request workflow builds, tests, packages and launches the real Release application on hosted Apple Silicon macOS (`macos-15`). The project and command-line gates force `ARCHS=arm64`, and release verification rejects universal or x86_64 executables.

The workflow executes deterministic unit/provider smoke tests and then runs the packaged `MacVitals.app` after a five-second warmup. Process CPU, resident memory, virtual memory, sample continuity and thread count are recorded in CSV and a schema-versioned JSON summary. The process must remain alive and pass broad runaway guardrails.

Runtime schema v3 uses a monotonic elapsed clock, rejects ambiguous process-name selection, pins the sampled process by PID, UID, start time and executable identity, and fails on possible PID reuse. The runtime evidence privacy gate rejects user home paths in generated CSV, JSON and logs.

Synchronous Mach, IOKit and Metal collection remains isolated in a dedicated `SystemSampler` actor, while UI publication remains on `MainActor`.

## Recorded hosted-runner baseline

The current runtime-hardening checkpoint is Pull Request workflow #247 for version `0.0.247` at feature head `d4a6da91c30e94db1add397d7387a0805c8cca69`. It is hosted regression evidence, not a physical-device performance claim.

Environment: hosted `arm64` macOS 15.7.7 (24G720), hardware model `VirtualMac2,1`, 3 logical CPUs and 7 GiB physical memory.

| Metric | Hosted arm64 observation |
|---|---:|
| Samples / duration | 24 / 46.0 s |
| Mean process CPU | 0.233% |
| p95 process CPU | 0.7% |
| Peak process CPU | 1.2% |
| Peak RSS | 53.53 MiB |
| RSS growth during measured window | -5.77 MiB |
| Peak threads | 5 |
| Process alive at completion | yes |
| Application runtime log | empty |
| Runtime evidence home-path scan | pass |

The same workflow completed 138 unit/provider tests, bilingual Preferences smoke and exact arm64-only ZIP/DMG verification before launching the packaged application. The negative RSS delta is an observation from this short hosted run, not a memory-reclamation guarantee.

## CI guardrails

The default CI validator rejects:

- unstable or incomplete process identity;
- ambiguous process selection or a non-monotonic elapsed clock;
- application exit before collection completes;
- fewer than 10 samples or less than 30 seconds of observation;
- severe sample cadence stalls;
- mean process CPU above 75% or p95 above 200%;
- peak RSS above 512 MiB;
- RSS growth above 128 MiB during the warmed measurement window;
- more than 128 threads when the platform exposes thread count;
- user home paths in runtime evidence files.

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
