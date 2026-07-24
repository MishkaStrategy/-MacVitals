# Audit 5: Security and release

Status: **automated controls completed for the Apple Silicon scope**.

Audited runtime-hardening head: `d4a6da91c30e94db1add397d7387a0805c8cca69`.

Primary evidence: Pull Request workflow #247 on hosted Apple Silicon macOS 15.7.7 (`arm64`).

## Scope

- repository and secret safety;
- Swift 6 ARM build and test evidence;
- localization and application-icon integrity;
- unsigned release packaging and provenance;
- architecture enforcement;
- packaged-application runtime smoke;
- process identity, timing and runtime-evidence privacy;
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

### Medium: runtime sampling could attach evidence to the wrong process

Evidence: the previous collector selected the first exact-name PID, used wall-clock elapsed time and sampled CPU/RSS/VSZ in separate `ps` invocations without a stable process identity contract. Ambiguous duplicate processes, clock corrections and PID reuse could make the evidence misleading.

Resolution: runtime schema v3 uses monotonic time, refuses ambiguous exact-name matches, supports an explicit PID/executable gate and pins every sample by PID, UID, start time and executable identity. Possible PID reuse terminates collection instead of silently continuing. Collector and validator adversarial self-tests run in PR, main and release-candidate workflows.

Status: **fixed and verified by workflow #247**.

### Medium: runtime evidence log exposed the hosted runner home path

Evidence: the first schema-v3 artifact correctly omitted paths from CSV/JSON, but successful console messages still recorded an absolute `/Users/runner/...` summary/output path in the uploaded runtime log.

Resolution: collector-wrapper and runtime-smoke messages now redact or omit home paths. A dedicated privacy gate scans generated runtime CSV, JSON and logs and fails on `/Users/<name>` or `/home/<name>` paths. The downloaded workflow #247 artifact was independently searched and contained no home path.

Status: **fixed and independently rechecked**.

### Medium: zero battery flow was labelled as charging

Evidence: every non-negative value selected the charging label, so a full battery reporting exactly `0 W` was shown as charging.

Resolution: the UI now distinguishes supporting the system, charging, no net battery flow and unavailable data.

Status: **fixed and covered by unit tests**.

### Medium: unavailable GPU memory topology was labelled discrete

Evidence: optional `hasUnifiedMemory` was collapsed with `?? false`, converting an unknown capability into a discrete-memory claim.

Resolution: unknown topology now displays `memory type unavailable` in English and Russian.

Status: **fixed and covered by unit tests**.

## Automated evidence

Workflow #247 completed successfully with:

- repository validation, collector/validator self-tests and secret scanning;
- SwiftFormat and native `arm64` build;
- 138 unit/provider tests with zero failures;
- English/Russian five-tab Preferences accessibility smoke;
- unsigned arm64-only Release archive;
- ZIP, DMG, application icon, checksum and provenance verification;
- packaged-app runtime smoke with stable process identity, monotonic timing, process alive at completion and an empty application log;
- runtime evidence privacy validation with no user home path.

Verified candidate: `MacVitals-0.0.247-arm64-unsigned`.

Workflow artifact digest: `sha256:fdabbbdf91e58d4391998f71413979e90b8d9402e063703bf81e2ae917823b90`.

Runtime evidence: 24 samples over 46.0 seconds, mean CPU 0.233%, p95 CPU 0.7%, peak CPU 1.2%, peak RSS 53.53 MiB, RSS delta -5.77 MiB and five threads.

## Security and publication decision

Automated controls pass for an internal unsigned Apple Silicon candidate. The tag-validation workflow remains read-only and cannot publish a public GitHub Release.

Public release remains blocked until Developer ID signing, Apple notarization, stapling, Gatekeeper validation on a clean Apple Silicon Mac and independent reviewer sign-off are completed. Physical battery/adapter transitions, Instruments energy/wakeup evidence, multi-hour stability and manual accessibility/visual review also remain open.

The separate `final-independent-audit.md` is intentionally still not marked complete.
