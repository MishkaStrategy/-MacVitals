# Changelog

## 1.0.0 - Unreleased

- Initial native menu bar application
- CPU, memory, battery, adapter and Metal capability providers
- Charger sufficiency evaluator with rolling median and conflict detection
- Customizable combined menu bar presets and ordering
- Diagnostics export, localization resources and privacy documentation
- Project-owned reproducible macOS application icon
- Bilingual five-tab Preferences accessibility smoke coverage
- Apple Silicon (`arm64`) only support contract for macOS 13+
- arm64-only CI, unsigned release packaging and exact architecture verification
- Intel compatibility workflow and universal binary requirements removed
- Runtime evidence schema v3 with monotonic timing and stable process identity
- Ambiguous process selection and possible PID reuse now fail closed
- Runtime evidence logs redact home paths and pass an automated privacy scan
- Reproducible physical Apple Silicon validation harness and runbook
- Every physical scenario is pinned to the verified candidate executable SHA-256
- Guarded private Developer ID signing/notarization workflow with exact commit binding
- Separate app and DMG signing, notarization logs, stapling and Gatekeeper verification
- Private signed artifacts remain non-public until independent review and explicit authorization
- Physical, manual, Instruments, independent-review and publication gates remain visibly incomplete until explicitly reviewed
