# Optimization Round 20: Release candidate stabilization

Status: **completed for hosted Apple Silicon evidence**.

Audited feature head: `384360f4a5593b0fc202f9ac51107f33203c7746`.

Primary evidence: Pull Request workflow #234, candidate `MacVitals-0.0.234-arm64-unsigned`.

## Baseline measurement

Hosted Apple Silicon environment:

- architecture: `arm64`;
- hardware model: `VirtualMac2,1`;
- macOS: 15.7.7 (24G720);
- logical CPUs: 3;
- physical memory: 7 GiB;
- requested runtime: 45 seconds at a 2-second interval;
- observed runtime: 22 samples over 46 seconds.

Observed packaged-process metrics:

| Metric | Result |
|---|---:|
| Mean CPU | 0.291% |
| p95 CPU | 1.1% |
| Peak CPU | 1.4% |
| Peak RSS | 51.80 MiB |
| RSS growth | 0.23 MiB |
| Peak threads | 5 |
| Process alive at completion | yes |
| Application log | empty |

## Hypothesis

Narrowing the product and release pipeline to Apple Silicon only, rejecting ambiguous sensor values and correcting misleading display fallbacks should improve release determinism and semantic correctness without causing a process-level CPU, memory or thread regression.

## Change

- removed Intel CI and universal binary requirements;
- enforced an exact arm64 executable throughout project generation, local commands, CI, packaging and provenance validation;
- corrected zero battery flow labelling;
- stopped guessing discrete GPU memory when the capability is unavailable;
- rejected zero battery voltage as missing telemetry;
- rejected missing or unrecognized internal-battery power-source states;
- added regression coverage for all corrected states.

## Tests and repeated measurement

Workflow #234 passed:

- repository/tooling/localization/icon validation and secret scan;
- native ARM build;
- 133 unit/provider tests with zero failures;
- English/Russian Preferences UI smoke;
- arm64-only unsigned ZIP/DMG packaging and provenance verification;
- packaged application runtime smoke.

The runtime validator confirmed sample continuity, broad CPU/RSS/thread guardrails and process survival. The verified candidate artifact digest is `sha256:52949659039eb6d82a6b905f428159fe3da73d959208592615943fbc458479d3`.

## Decision

**Keep.** The stabilization changes improved architecture consistency and sensor/UI honesty while the packaged ARM process remained well inside broad hosted regression guardrails.

This round does not replace physical Apple Silicon MacBook battery/adapter testing, Instruments energy and wakeup traces, sleep/wake validation, multi-hour stability or a final independent audit.
