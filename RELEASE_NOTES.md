# MacVitals 1.0.0

## Overview
Native privacy-first macOS menu bar diagnostics for Apple Silicon Macs.

## Highlights
CPU and memory monitoring, battery/adapter diagnostics, bounded history, configurable combined menu bar, support bundle export and charger sufficiency assessment.

## Metrics
Direct/derived/experimental quality and source metadata accompany measurements. Adapter rated power is never represented as measured input power.

## Menu Bar Customization
Presets and metric ordering are included. Separate status items remain experimental and disabled.

## Power Sufficiency
Uses sustained signed battery power while external power is connected, rolling median, minimum duration and sensor-conflict handling.

## Visual Identity and Accessibility
Includes a project-owned, reproducibly materialized macOS application icon. English and Russian Preferences smoke coverage verifies all five tabs and their stable accessibility surfaces.

## Privacy
No accounts, telemetry, analytics, ads, network backend, root helper or `sudo`. Runtime performance evidence uses monotonic timing and stable PID/UID/start-time/executable identity, refuses ambiguous process selection, detects possible PID reuse and automatically rejects user home paths in generated CSV, JSON and logs.

## Compatibility
macOS 13+ on Apple Silicon (`arm64`) only. Intel (`x86_64`) and universal builds are not supported. Runtime capability checks decide sensor availability on supported hardware.

## Installation
The CI fallback build is unsigned and non-notarized unless valid Apple credentials were configured for the workflow. `BUILD_STATUS.txt` must report `Architectures: arm64`.

## Known Limitations
Whole-system GPU utilization and measured adapter input power may be unavailable. Hardware performance, VoiceOver and final visual evidence must be collected on representative physical Apple Silicon Mac hardware.

## Checksums
See `SHA256SUMS.txt` attached to the release.

## Build Information
Swift 6 / Xcode Apple Silicon macOS runner. The attached `BUILD_STATUS.txt` is authoritative for architecture, signing and notarization status.
