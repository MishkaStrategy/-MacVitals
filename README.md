# MacVitals

MacVitals is a native, privacy-first macOS menu bar monitor for Apple Silicon Macs. It keeps the most useful system indicators close at hand without accounts, telemetry, advertising or a cloud service.

The app combines live CPU and memory information, battery and charger diagnostics, temperature readings, process consumers, power-flow interpretation and read-only fan monitoring in a compact SwiftUI interface.

> **Development status:** MacVitals v1 is under active validation in Draft PR #1. The current unsigned Apple Silicon build passes hosted arm64 build, test, packaging and runtime checks, as well as physical read-only fan and direct-session validation. Developer ID signing, notarization, final accessibility review and public release remain intentionally incomplete.

## What MacVitals shows

- CPU usage from delta-based Mach host counters
- Memory usage and native macOS memory-pressure state
- Battery level, charging state, health and capability-checked extended fields
- Adapter rated and negotiated power, kept separate from measured input power
- Direct or derived system-power telemetry with clear source labels
- Battery and processor temperature when supported by the current Mac
- Metal GPU identity and capabilities without fabricated utilization values
- Read-only fan RPM, limits and operating mode through AppleSMC
- Top process consumers for quicker diagnosis of unexpected load
- Bounded metric history with sleep and wake discontinuities
- Local alerts with cooldown and explicit notification permission handling

## Interface

MacVitals lives in the macOS menu bar. Opening it reveals an overview with clickable metric cards. Detailed views provide recent history and supporting values, while Preferences contains separate sections for general behavior, alerts, menu-bar content, fan monitoring, diagnostics and privacy.

The interface is available in English and Russian and is built with native SwiftUI and AppKit components.

## Real application screenshots

These screenshots were captured automatically from the actual MacVitals application built and launched on a GitHub-hosted macOS 15 ARM64 runner. They are direct XCTest window captures, not mockups or concept renders. Hardware-dependent values reflect the CI runner, so unavailable battery, adapter or fan providers are expected there.

<table>
  <tr>
    <td width="50%"><strong>General settings</strong><br><img src="docs/screenshots/preferences-general.png" alt="MacVitals General settings" width="100%"></td>
    <td width="50%"><strong>Menu bar configuration</strong><br><img src="docs/screenshots/preferences-menu-bar.png" alt="MacVitals menu bar configuration" width="100%"></td>
  </tr>
  <tr>
    <td width="50%"><strong>Fan monitoring and safety</strong><br><img src="docs/screenshots/preferences-fans.png" alt="MacVitals fan monitoring and safety settings" width="100%"></td>
    <td width="50%"><strong>Diagnostics</strong><br><img src="docs/screenshots/preferences-diagnostics.png" alt="MacVitals diagnostics screen" width="100%"></td>
  </tr>
</table>

The reproducible capture workflow is available in [`.github/workflows/readme-screenshots.yml`](.github/workflows/readme-screenshots.yml).

## Supported platform

- Apple Silicon (`arm64`) only
- macOS 13 or later
- Intel (`x86_64`) and universal release binaries are intentionally rejected

## Privacy

All metrics are processed locally. MacVitals makes no network requests and contains no accounts, analytics, telemetry, advertising or cloud backend. Diagnostic and runtime evidence is designed to omit usernames, home paths, serial numbers, Apple IDs, user documents and network data.

See [PRIVACY.md](PRIVACY.md).

## Important limitations

- macOS does not expose one universal public API for reliable whole-system GPU utilization across supported Macs. MacVitals reports the metric as unavailable when no trustworthy provider exists.
- Nominal adapter power is never presented as live system consumption.
- Extended battery fields from IORegistry are capability-checked and marked experimental.
- Fan monitoring is read-only in unsigned builds. Physical fan control is not claimed as working or release-ready.
- Hosted runtime measurements are regression evidence for specific runners, not universal performance promises.

## Build from source

Requirements: Apple Silicon Mac, macOS 13+, Xcode 16+, Homebrew.

```bash
git clone https://github.com/MishkaStrategy/-MacVitals.git
cd -- -MacVitals
git switch feature/macvitals-v1
make bootstrap
open MacVitals.xcodeproj
```

Run validation and tests:

```bash
make validate-tooling
make test
```

Create an explicitly unsigned local package:

```bash
make package VERSION=0.0.0
```

The package output includes:

- `MacVitals-<version>.zip`
- `MacVitals-<version>.dmg`
- `SHA256SUMS.txt`
- `BUILD_STATUS.txt`
- `BUILD_MANIFEST.json`

Run the packaged-app runtime smoke used by CI:

```bash
make runtime-smoke VERSION=0.0.0
```

Collect a longer process-level CSV/JSON record from an already running instance:

```bash
make collect-runtime RUNTIME_DURATION=900 RUNTIME_INTERVAL=2
```

These process samples do not replace Instruments energy, wakeup, thermal or physical battery testing.

## Validation status

The current validation pipeline covers:

- formatting and generated-project checks;
- native Apple Silicon build and automated tests;
- packaged application runtime smoke;
- arm64-only unsigned ZIP and DMG packaging;
- application icon, localization, checksum and provenance verification;
- English and Russian Preferences accessibility smoke;
- reproducible real-application screenshot capture;
- physical read-only fan RPM evidence;
- physical direct-session stability and Instruments collection.

## Remaining release gates

- Developer ID signing, notarization, stapling and clean-Mac Gatekeeper validation
- Final manual VoiceOver, keyboard and EN/RU visual review
- Representative physical Apple Silicon screenshot and visual review
- Independent review of physical and Instruments evidence
- Explicit authorization before merge, tag or public release

## Documentation

- [Russian README](README_RU.md)
- [Architecture](ARCHITECTURE.md)
- [Privacy](PRIVACY.md)
- [Application icon](docs/APP_ICON.md)
- [Power model](docs/POWER_MODEL.md)
- [Sensor compatibility](docs/SENSOR_COMPATIBILITY.md)
- [Performance evidence](docs/PERFORMANCE.md)
- [Build provenance](docs/BUILD_PROVENANCE.md)
- [Release process](docs/RELEASE.md)
