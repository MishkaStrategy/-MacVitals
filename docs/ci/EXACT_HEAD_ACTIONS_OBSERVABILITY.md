# Exact-head Actions observability

## Scope

This document records the CI observability blocker for the current network/history integration candidate. It does not change product code or relax any acceptance gate.

## Exact candidate

- Product PR: `#125`
- Product branch: `integration/network-history-leaders-post-notch`
- Exact head: `72e482c11cfd9a1bcd8778b70df905805d1319be`
- Validation PR: `#132`
- Validation branch: `validation/exact-head-network-history-72e482c1`
- Protected product ancestor: `4d143aaa082b0fb15ce86d19ba72c40557939692`
- Stacked base: `perf/provider-stack-long-baseline`
- Exact stacked base SHA: `7462578a8e622fd409d7bf1269a6c2b451676514`

## Expected checks

The candidate declares the following pull-request workflows:

- `Pull Request`
- `Exact Head Candidate`
- `UI Test Compile Guard`
- `Runtime Resource Evidence Policy`
- `Physical Runtime Safety`

The physical runtime jobs use the shared `macvitals-physical-runtime` concurrency group with `queue: max`, `cancel-in-progress: false`, and a host-level fail-closed lock.

## Observed API state

For both the product head and the immutable validation head, the connected GitHub Actions API currently returns:

- no pull-request workflow run objects;
- no commit status contexts;
- therefore no run IDs, job IDs, logs, steps, or artifacts that can be independently verified.

This observation does **not** prove that GitHub Actions created no check suite. The connected API is narrower than the full Actions UI/API and may not expose approval-required or otherwise pending workflow runs.

## Allowed resolution

Before any acceptance or merge decision, one of the following must produce verifiable run IDs:

1. approve any approval-required workflows for validation PR `#132` in the GitHub UI;
2. dispatch the workflows explicitly using a credential/action that can create `workflow_dispatch` runs;
3. expose the relevant Actions run/check-suite endpoint through the connected GitHub integration;
4. reproduce the exact-head checks through an already trusted workflow on a branch where Actions execution is observable.

## Non-resolution

The following are not substitutes for exact-head evidence:

- old green runs for `6c42502b10c12ecc67e0c7b04b6eb6924cf87136`;
- runs that built GitHub's synthetic merge ref instead of the branch head;
- static YAML review alone;
- benchmark or physical evidence from a stale product base.

## Safety

No direct `main` changes, merge, release, signing, notarization, privileged helper registration, SMC writes, or fan RPM changes are permitted while this blocker remains open.
