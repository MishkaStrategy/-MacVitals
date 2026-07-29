# Optimization Round 20: Release candidate stabilization

Status: **completed for hosted Apple Silicon evidence**.

Audited runtime-hardening head: `d4a6da91c30e94db1add397d7387a0805c8cca69`.

Primary evidence: Pull Request workflow #247, candidate `MacVitals-0.0.247-arm64-unsigned`.

## Baseline measurement

Hosted Apple Silicon environment:

- architecture: `arm64`;
- hardware model: `VirtualMac2,1`;
- macOS: 15.7.7 (24G720);
- logical CPUs: 3;
- physical memory: 7 GiB;
- requested runtime: 45 seconds at a 2-second interval;
- observed runtime: 24 samples over 46.0 seconds.

Observed packaged-process metrics:

| Metric | Result |
|---|---:|
| Mean CPU | 0.233% |
| p95 CPU | 0.7% |
| Peak CPU | 1.2% |
| Peak RSS | 53.53 MiB |
| RSS growth | -5.77 MiB |
| Peak threads | 5 |
| Process alive at completion | yes |
| Application log | empty |
| Runtime evidence home-path scan | pass |

## Hypothesis

Narrowing the product and release pipeline to Apple Silicon only, rejecting ambiguous sensor values and correcting misleading display fallbacks should improve release determinism and semantic correctness without causing a process-level CPU, memory or thread regression. Hardening the runtime evidence collector should also prevent clock changes, PID reuse, ambiguous process selection or host-path leakage from producing trustworthy-looking evidence.

## Change

- removed Intel CI and universal binary requirements;
- enforced an exact arm64 executable throughout project generation, local commands, CI, packaging and provenance validation;
- corrected zero battery flow labelling;
- stopped guessing discrete GPU memory when the capability is unavailable;
- rejected zero battery voltage as missing telemetry;
- rejected missing or unrecognized internal-battery power-source states;
- moved runtime elapsed measurement to a monotonic clock;
- pinned runtime samples by PID, UID, process start time and executable identity;
- made duplicate exact-name matches and possible PID reuse fail closed;
- added collector/validator adversarial self-tests to PR, main and release workflows;
- removed absolute home paths from runtime console output and added an evidence privacy scan;
- added regression coverage for corrected application states.

## Tests and repeated measurement

Workflow #247 passed:

- repository/tooling/localization/icon validation and secret scan;
- native ARM build;
- 138 unit/provider tests with zero failures;
- English/Russian Preferences UI smoke;
- arm64-only unsigned ZIP/DMG packaging and provenance verification;
- packaged application runtime smoke;
- process identity, monotonic timing and runtime-evidence privacy gates.

The runtime validator confirmed stable process identity, sample continuity, broad CPU/RSS/thread guardrails and process survival. Independent artifact inspection confirmed the application log was empty and no `/Users/<name>` or `/home/<name>` path remained in the uploaded runtime evidence. The verified candidate artifact digest is `sha256:fdabbbdf91e58d4391998f71413979e90b8d9402e063703bf81e2ae917823b90`.

## Decision

**Keep.** The stabilization changes improved architecture consistency, sensor/UI honesty and runtime-evidence integrity while the packaged ARM process remained well inside broad hosted regression guardrails.

This round does not replace physical Apple Silicon MacBook battery/adapter testing, Instruments energy and wakeup traces, sleep/wake validation, multi-hour stability or a final independent audit.
