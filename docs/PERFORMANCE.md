# Performance

## Verified evidence

The macOS ARM pull-request workflow now builds and launches MacVitals, executes the provider-backed `SystemSampler` smoke test and verifies that a coherent hardware snapshot is produced. Synchronous Mach, IOKit and Metal collection is isolated in a dedicated actor, while UI publication remains on `MainActor`.

This confirms functional sampling on a hosted Apple Silicon macOS runner. It is **not** an idle-power, wakeup, memory-footprint or long-duration performance benchmark.

## Measurement still required

A physical-device benchmark must record:

- exact Mac model, CPU/GPU, memory and macOS build;
- power mode and whether the Mac is on battery or external power;
- sampling interval and test duration;
- average, p95 and peak process CPU;
- resident and virtual memory;
- thread count and wakeups;
- energy impact or equivalent Instruments evidence;
- behavior while the popover is closed and open;
- sleep/wake recovery;
- provider latency and missing-data behavior.

The primary target profile is a MacBook Pro with M1 Pro at the default 2-second interval. The app must perform no continuous network activity, subprocess polling or periodic disk writes. No numerical performance target is claimed as achieved until measured evidence is committed.
