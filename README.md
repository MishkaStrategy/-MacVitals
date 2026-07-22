# MacVitals

MacVitals is a lightweight, privacy-first native macOS menu bar utility for CPU, memory, battery, adapter and real-time power diagnostics.

> **Release status:** the repository contains the v1 implementation and macOS CI. A build must pass on a real Mac runner before any artifact is described as verified. Unsigned CI artifacts are never described as notarized.

## Highlights

- Native SwiftUI + AppKit menu bar application for macOS 13+
- CPU usage from delta-based Mach host counters
- Memory details from `host_statistics64`
- Battery state through public IOKit Power Sources APIs
- Capability-checked extended battery fields from IORegistry, marked experimental
- Adapter rated/negotiated power kept separate from measured input power
- Robust charger sufficiency window based primarily on sustained battery discharge while external power is connected
- Metal GPU identity and capability detection; no fabricated system utilization
- Bounded in-memory history with sleep/wake discontinuities
- English and Russian localization resources
- No accounts, ads, analytics, telemetry, cloud backend, root helper or `sudo`

## GPU limitation

macOS does not expose one universal public API for whole-system GPU utilization across supported Macs. MacVitals therefore shows Metal device information and reports system GPU utilization as unavailable when no reliable provider exists.

## Build from source

Requirements: macOS 13+, Xcode 16+, Homebrew.

```bash
git clone https://github.com/mishkacher/-MacVitals.git
cd -- -MacVitals
make bootstrap
open MacVitals.xcodeproj
```

For command-line tests:

```bash
make test
```

## Screenshots

Verified screenshots will be added only after the application has been built and captured on a macOS runner. Concept renders are intentionally not presented as real screenshots.

## Privacy

All metrics are processed locally. MacVitals makes no network requests and contains no telemetry. See [PRIVACY.md](PRIVACY.md).

## Power sufficiency

The evaluator does **not** compare voltages. Its most important practical signal is sustained battery discharge while external power is connected. It uses a rolling window, median smoothing, minimum duration and conflict detection. Nominal adapter power is never presented as live consumption.

## Roadmap

- Verified Apple Silicon hardware matrix
- Signed and notarized distribution when Apple credentials are available
- Optional, isolated GPU providers only when a stable legal/public source is proven
- Expanded menu bar icon customization and safe local SVG/PDF import

See [README_RU.md](README_RU.md), [architecture](ARCHITECTURE.md), [sensor compatibility](docs/SENSOR_COMPATIBILITY.md), and [known release process](docs/RELEASE.md).
