# Performance

## What CI now proves

The pull-request workflows build and launch the packaged Release application on two independent hosted macOS architectures:

- Apple Silicon on `macos-15`;
- Intel x86_64 on `macos-15-intel`.

Both workflows execute deterministic unit/provider smoke tests and then run the real packaged `MacVitals.app` after a five-second warmup. Process CPU, resident memory, virtual memory, sample continuity and thread count are recorded in CSV and a schema-versioned JSON summary. The process must remain alive and pass broad runaway guardrails.

Synchronous Mach, IOKit and Metal collection remains isolated in a dedicated `SystemSampler` actor, while UI publication remains on `MainActor`.

## Recorded hosted-runner evidence

These observations are retained in the workflow artifacts for the named runs. They describe only the recorded virtual runners and workloads.

| Evidence | ARM pull-request run 151 | Intel compatibility run 2 |
|---|---:|---:|
| Source commit | `7ab19e12c65014a6afbd6efcd684f2c979fa4379` | `5c2fd8763de9ee5768f86d148db8e23e3584e5b7` |
| Architecture | arm64 | x86_64 |
| Hosted hardware model | `VirtualMac2,1` | `Macmini6,2` |
| macOS | 15.7.7 (24G720) | 15.7.7 (24G720) |
| Warmup | 5 s | 5 s |
| Measured duration | 46 s | 31 s |
| Samples | 22 | 15 |
| Mean process CPU | 0.23% | 0.07% |
| p95 process CPU | 1.00% | 0.30% |
| Peak RSS | 54.27 MiB | 33.96 MiB |
| RSS growth during measured window | 0.17 MiB | 0.08 MiB |
| Peak threads | 5 | 6 |
| Process alive at completion | yes | yes |

The ARM run intentionally supersedes the earlier no-warmup smoke, where startup allocation inflated the apparent RSS growth. The current measured window begins only after application initialization.

## CI guardrails

The default CI validator rejects:

- application exit before collection completes;
- fewer than 10 samples or less than 30 seconds of ARM observation;
- severe sample cadence stalls;
- mean process CPU above 75% or p95 above 200% on the ARM guardrail;
- peak RSS above 512 MiB;
- RSS growth above 128 MiB during the warmed measurement window;
- more than 128 threads when the platform exposes thread count.

The Intel job uses a shorter 30-second observation and slightly wider CPU limits while keeping the same memory and thread runaway limits.

These thresholds are deliberately broad regression alarms. They are **not** product targets, service-level objectives or claims that all Macs will match the hosted values.

## What this does not prove

Hosted CI is not an idle-power, wakeup, thermal, battery-runtime or long-duration stability benchmark. It also does not reproduce physical MacBook battery/adapter semantics.

A physical-device benchmark must still record:

- exact Mac model, CPU/GPU, memory and macOS build;
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