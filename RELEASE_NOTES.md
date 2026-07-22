# MacVitals 1.0.0

## Overview
Native privacy-first macOS menu bar diagnostics.

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
No accounts, telemetry, analytics, ads, network backend, root helper or `sudo`.

## Compatibility
macOS 13+; Apple Silicon is the primary target. Runtime capability checks decide sensor availability.

## Installation
The CI fallback build is unsigned and non-notarized unless valid Apple credentials were configured for the workflow.

## Known Limitations
Whole-system GPU utilization and measured adapter input power may be unavailable. Hardware performance, VoiceOver and final visual evidence must be collected on representative physical Mac hardware.

## Checksums
See `SHA256SUMS.txt` attached to the release.

## Build Information
Swift 6 / Xcode macOS runner. The attached `BUILD_STATUS.txt` is authoritative for signing/notarization status.
