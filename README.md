# MacVitals

MacVitals is a lightweight, privacy-first native macOS menu bar utility for CPU, memory, battery, adapter and real-time power diagnostics.

> **Release status:** Apple Silicon and Intel hosted macOS workflows now verify formatting, native builds, unit/provider tests, packaged-app runtime smoke, universal unsigned Release packaging, ZIP/DMG consistency, EN/RU resources, SHA-256 checksums and machine-readable build provenance. Apple signing, notarization, physical battery/adapter validation, Instruments energy measurements and final hardware screenshots remain incomplete.

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
- Reproducible unsigned ZIP and DMG packaging with provenance and checksum verification
- Native hosted runtime smoke on both arm64 and x86_64
- English and Russian localization resources and UI smoke coverage
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

For command-line validation and tests:

```bash
make validate-tooling
make test
```

For an explicitly unsigned local package:

```bash
make package VERSION=0.0.0
```

The package output includes:

- `MacVitals-<version>.zip`
- `MacVitals-<version>.dmg`
- `SHA256SUMS.txt`
- `BUILD_STATUS.txt`
- `BUILD_MANIFEST.json`

The verifier checks the bundle, localizations, universal executable, ZIP/DMG payload consistency, signing/notarization classification and exact checksum scope. An artifact must not be described as Developer ID signed or notarized unless the actual bundle and provenance checks confirm those states.

To run the same short packaged-app regression guardrail used by CI:

```bash
make runtime-smoke VERSION=0.0.0
```

To collect a longer process-level CSV/JSON record from an already running MacVitals instance:

```bash
make collect-runtime RUNTIME_DURATION=900 RUNTIME_INTERVAL=2
```

These process samples do not replace Instruments energy, wakeup, thermal or physical battery testing.

## Verified hosted evidence

The current workflows have successfully:

- built, tested and launched the packaged app natively on hosted arm64 macOS;
- built, tested and launched a native x86_64 app on `macos-15-intel`;
- retained raw runtime CSV/JSON evidence;
- kept broad CPU, RSS, sample-continuity and thread-count runaway guardrails green.

This confirms hosted architecture compatibility. It does not prove physical MacBook battery, charger, thermal, sleep/wake or energy behavior. See [performance evidence](docs/PERFORMANCE.md) and [physical validation protocol](docs/HARDWARE_VALIDATION.md).

## Screenshots

Verified screenshots will be added only after the application has been captured on representative physical Mac hardware. Concept renders are intentionally not presented as real screenshots.

## Privacy

All metrics are processed locally. MacVitals makes no network requests and contains no telemetry. Support and runtime evidence are designed to omit usernames, home paths, serial numbers, Apple ID, user documents and network data. See [PRIVACY.md](PRIVACY.md).

## Power sufficiency

The evaluator does **not** compare voltages. Its most important practical signal is sustained battery discharge while external power is connected. It uses a rolling window, median smoothing, minimum duration and conflict detection. Nominal adapter power is never presented as live consumption.

## Remaining release gates

- Apple Developer ID signing, notarization, stapling and Gatekeeper validation with real credentials
- Physical Apple Silicon laptop validation under battery/adapter transitions
- Physical Intel Mac validation for retained sensor claims, or explicitly narrowed support claims
- Instruments energy/wakeup/allocations evidence and multi-hour stability testing
- Final screenshots and accessibility pass on physical hardware
- Production application icon and final visual review

See [README_RU.md](README_RU.md), [architecture](ARCHITECTURE.md), [sensor compatibility](docs/SENSOR_COMPATIBILITY.md), [build provenance](docs/BUILD_PROVENANCE.md), and [release process](docs/RELEASE.md).