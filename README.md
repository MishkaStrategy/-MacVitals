# MacVitals

MacVitals is a lightweight, privacy-first native macOS menu bar utility for CPU, memory, battery, adapter and real-time power diagnostics.

> **Release status:** native macOS ARM CI now verifies formatting, Debug build, unit and hardware-smoke tests, an unsigned Release archive, ZIP, DMG, SHA-256 checksums, bundle metadata and a UI smoke test. Apple signing, notarization, physical-device performance measurements and the Intel hardware matrix are not complete.

## Highlights

- Native SwiftUI + AppKit menu bar application for macOS 13+
- CPU usage from delta-based Mach host counters
- Memory accounting from `host_statistics64`
- Native macOS memory-pressure transitions from `DispatchSourceMemoryPressure`
- Battery state through public IOKit Power Sources APIs
- Capability-checked extended battery fields from IORegistry, marked experimental
- Adapter rated/negotiated power kept separate from measured input power
- Robust charger sufficiency window based primarily on sustained battery discharge while external power is connected
- Metal GPU identity and capability detection; no fabricated system utilization
- Local state-transition alerts with cooldown and explicit permission handling
- Bounded in-memory history with sleep/wake discontinuities
- Reproducible unsigned ZIP and DMG packaging with verification and checksums
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

For an explicitly unsigned local package:

```bash
make package VERSION=0.0.0
```

The package output includes ZIP, DMG, `SHA256SUMS.txt` and `BUILD_STATUS.txt`. It must not be described as signed or notarized unless those status files explicitly confirm both states.

## Screenshots

Verified screenshots will be added only after the application has been captured on representative physical Mac hardware. Concept renders are intentionally not presented as real screenshots.

## Privacy

All metrics are processed locally. MacVitals makes no network requests and contains no telemetry. See [PRIVACY.md](PRIVACY.md).

## Power sufficiency

The evaluator does **not** compare voltages. Its most important practical signal is sustained battery discharge while external power is connected. It uses a rolling window, median smoothing, minimum duration and conflict detection. Nominal adapter power is never presented as live consumption.

## Remaining release gates

- Apple Developer ID signing and notarization with real credentials
- Physical Apple Silicon laptop validation under battery/adapter transitions
- Intel Mac validation
- Measured idle and active performance profile
- Final screenshots and accessibility pass on physical hardware

See [README_RU.md](README_RU.md), [architecture](ARCHITECTURE.md), [sensor compatibility](docs/SENSOR_COMPATIBILITY.md), and [release process](docs/RELEASE.md).
