# Audit 5: Security and release

Status: **automated controls completed for the Apple Silicon scope**.

Audited release-tooling head: `3d692c51e1199e13093bdc3aff0b4d881525dbfe`.

Primary evidence: Pull Request workflow #262 on hosted Apple Silicon macOS 15.7.7 (`arm64`).

## Scope

- repository and secret safety;
- Swift 6 ARM build and test evidence;
- localization and application-icon integrity;
- unsigned release packaging and provenance;
- architecture enforcement;
- packaged-application runtime smoke;
- process identity, timing and runtime-evidence privacy;
- physical-validation candidate binding and conservative acceptance state;
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

Status: **fixed and verified**.

### Medium: runtime evidence log exposed the hosted runner home path

Evidence: the first schema-v3 artifact correctly omitted paths from CSV/JSON, but successful console messages still recorded an absolute `/Users/runner/...` summary/output path in the uploaded runtime log.

Resolution: collector-wrapper and runtime-smoke messages now redact or omit home paths. A dedicated privacy gate scans generated runtime CSV, JSON and logs and fails on `/Users/<name>` or `/home/<name>` paths. Downloaded workflow artifacts were independently searched and contained no home path.

Status: **fixed and independently rechecked**.

### Medium: physical validation could drift from the verified candidate

Evidence: the project documented physical scenarios but did not provide a single tool that proved the tested application was the exact verified ZIP payload, preserved redacted machine/power evidence and kept every unperformed manual gate visibly open.

Resolution:

- added `scripts/run_physical_validation.py` and a dedicated runbook;
- candidate preparation reruns the complete release verifier;
- the tested application must match bundle ID, version, build, exact arm64 architecture and executable SHA-256 from the verified ZIP;
- every later scenario rechecks the same executable SHA-256;
- named scenarios store isolated runtime evidence and parsed power timelines;
- generated acceptance state starts with all physical/manual gates as `not-run` or `not-tested`;
- finalization remains incomplete until every required review is explicitly passed or honestly marked unsupported;
- the authoring assistant cannot use hosted preparation as physical-device evidence or as an independent reviewer sign-off.

Status: **implemented and hosted-prepare-smoked by workflow #262; real physical scenarios remain open**.

### Medium: zero battery flow was labelled as charging

Evidence: every non-negative value selected the charging label, so a full battery reporting exactly `0 W` was shown as charging.

Resolution: the UI now distinguishes supporting the system, charging, no net battery flow and unavailable data.

Status: **fixed and covered by unit tests**.

### Medium: unavailable GPU memory topology was labelled discrete

Evidence: optional `hasUnifiedMemory` was collapsed with `?? false`, converting an unknown capability into a discrete-memory claim.

Resolution: unknown topology now displays `memory type unavailable` in English and Russian.

Status: **fixed and covered by unit tests**.

## Automated evidence

Workflow #262 completed successfully with:

- repository validation, collector/validator/physical-harness self-tests and secret scanning;
- SwiftFormat and native `arm64` build;
- 138 unit/provider tests with zero failures;
- English/Russian five-tab Preferences accessibility smoke;
- unsigned arm64-only Release archive;
- ZIP, DMG, application icon, checksum and provenance verification;
- hosted physical-harness `prepare` smoke against the exact generated candidate;
- packaged-app runtime smoke with stable process identity, monotonic timing, process alive at completion and an empty application log;
- runtime and physical-harness evidence privacy validation with no user home path.

Verified candidate: `MacVitals-0.0.262-arm64-unsigned`.

Candidate workflow artifact digest: `sha256:3cb259cdd045936992408f72205fb7d3b7a1ba0736061d603657a79864a2f224`.

Hosted physical-harness artifact digest: `sha256:8ad13659c88a6cca57de457dd66a9cb7f470b96dcd864fcc3e5923618a4cece4`.

Runtime evidence artifact digest: `sha256:9fd4344f307f5a1b2e016411f168c435681d8ee7a5d3c51d879b178fa306ca08`.

Runtime evidence: 24 samples over 46.1 seconds, mean CPU 0.263%, p95 CPU 1.0%, peak CPU 1.3%, peak RSS 53.86 MiB, RSS growth 0.12 MiB and five threads.

Independent artifact inspection confirmed that the hosted physical session remained `prepared`, all real scenarios and manual gates remained `not-run`/`not-tested`, the candidate and tested executable SHA-256 matched, and no `/Users/<name>` or `/home/<name>` path appeared in either the physical-harness or runtime evidence.

## Security and publication decision

Automated controls pass for an internal unsigned Apple Silicon candidate. The tag-validation workflow remains read-only and cannot publish a public GitHub Release.

Public release remains blocked until Developer ID signing, Apple notarization, stapling, Gatekeeper validation on a clean Apple Silicon Mac and independent reviewer sign-off are completed. Physical battery/adapter transitions, Instruments energy/wakeup evidence, multi-hour stability and manual accessibility/visual review also remain open.

The separate `final-independent-audit.md` is intentionally still not marked complete.
