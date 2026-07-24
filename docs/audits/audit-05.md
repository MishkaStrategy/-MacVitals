# Audit 5: Security and release

Status: **automated controls completed for the Apple Silicon scope**.

Audited feature head: `384360f4a5593b0fc202f9ac51107f33203c7746`.

Primary evidence: Pull Request workflow #234 on hosted Apple Silicon macOS 15.7.7 (`arm64`).

## Scope

- repository and secret safety;
- Swift 6 ARM build and test evidence;
- localization and application-icon integrity;
- unsigned release packaging and provenance;
- architecture enforcement;
- packaged-application runtime smoke;
- misleading sensor and UI states found during continuation review.

Intel and universal binaries are intentionally outside the supported product scope.

## Findings and resolution

### High: release contract still required Intel/universal artifacts

Evidence: the former Intel workflow and release verifier expected an `arm64 x86_64` executable even though the supported product is Apple Silicon only.

Resolution:

- removed the Intel workflow;
- forced `ARCHS=arm64` in XcodeGen, local Make targets and active macOS workflows;
- made packaging and metadata validation require exactly `arm64`;
- made universal, `x86_64` and additional slices verification failures;
- aligned current build, release, provenance, compatibility and contributor documentation.

Status: **fixed and verified**.

### High: zero battery voltage could become a trustworthy-looking `0 W`

Evidence: `0 mV` passed normalization and could be multiplied by a valid current. A sustained false zero could bias charger-sufficiency output toward a non-discharge state.

Resolution: voltage must now be finite and strictly positive; power calculation also rejects non-positive voltage and non-finite current while preserving a valid zero-current reading.

Status: **fixed and covered by unit tests**.

### High: unknown battery power-source state was treated as disconnected

Evidence: a missing or unrecognized `kIOPSPowerSourceStateKey` compared unequal to AC power and silently became `externalPowerConnected = false`.

Resolution: only the documented AC and battery states are accepted. Missing or unknown states produce an explicit provider error and cannot enter the charger-sufficiency evidence window.

Status: **fixed and covered by unit tests**.

### Medium: zero battery flow was labelled as charging

Evidence: every non-negative value selected the charging label, so a full battery reporting exactly `0 W` was shown as charging.

Resolution: the UI now distinguishes supporting the system, charging, no net battery flow and unavailable data.

Status: **fixed and covered by unit tests**.

### Medium: unavailable GPU memory topology was labelled discrete

Evidence: optional `hasUnifiedMemory` was collapsed with `?? false`, converting an unknown capability into a discrete-memory claim.

Resolution: unknown topology now displays `memory type unavailable` in English and Russian.

Status: **fixed and covered by unit tests**.

## Automated evidence

Workflow #234 completed successfully with:

- repository validation and secret scanning;
- SwiftFormat and native `arm64` build;
- 133 unit/provider tests with zero failures;
- English/Russian five-tab Preferences accessibility smoke;
- unsigned arm64-only Release archive;
- ZIP, DMG, application icon, checksum and provenance verification;
- packaged-app runtime smoke with process alive at completion and an empty application log.

Verified candidate: `MacVitals-0.0.234-arm64-unsigned`.

Artifact digest: `sha256:52949659039eb6d82a6b905f428159fe3da73d959208592615943fbc458479d3`.

## Security and publication decision

Automated controls pass for an internal unsigned Apple Silicon candidate. The tag-validation workflow remains read-only and cannot publish a public GitHub Release.

Public release remains blocked until Developer ID signing, Apple notarization, stapling, Gatekeeper validation on a clean Apple Silicon Mac and independent reviewer sign-off are completed. Physical battery/adapter transitions, Instruments energy/wakeup evidence, multi-hour stability and manual accessibility/visual review also remain open.

The separate `final-independent-audit.md` is intentionally still not marked complete.
