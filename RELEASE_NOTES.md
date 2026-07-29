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

## Physical Validation
A reproducible Apple Silicon validation harness verifies the candidate manifest, checksums, exact arm64 architecture and executable SHA-256 before collecting isolated battery, adapter, sleep/wake and stability evidence. It keeps every physical, manual, Instruments, independent-review and publication gate visibly incomplete until an authorized reviewer records the result.

## Signed Candidate Safety
A separate protected manual workflow can create a private Developer ID signed and notarized candidate for an exact commit. It signs and notarizes both the application and DMG, retains Apple logs, validates stapled tickets and Gatekeeper, regenerates final checksums and has read-only repository permissions. It does not merge, tag or create a public GitHub Release.

## Compatibility
macOS 13+ on Apple Silicon (`arm64`) only. Intel (`x86_64`) and universal builds are not supported. Runtime capability checks decide sensor availability on supported hardware.

## Installation
Normal CI candidates are unsigned and non-notarized. A private signed workflow artifact may report `developer-id-signed` and `ticket-present` only after all signature, Apple notarization, stapling and hosted Gatekeeper gates pass. `BUILD_STATUS.txt` must report `Architectures: arm64`.

## Known Limitations
Whole-system GPU utilization and measured adapter input power may be unavailable. Hardware performance, VoiceOver and final visual evidence must be collected on representative physical Apple Silicon Mac hardware. Hosted preparation of the physical-validation harness is not physical-device evidence, and a hosted Gatekeeper pass does not replace clean-Mac installation validation.

## Checksums
See `SHA256SUMS.txt` attached to the release.

## Build Information
Swift 6 / Xcode Apple Silicon macOS runner. The attached `BUILD_STATUS.txt` is authoritative for architecture, signing and notarization status.
