# MacVitals test resource monitoring

## Owner requirement

Every future test that launches the real `MacVitals` process must measure how much CPU and memory the application consumes. The evidence is retained to compare revisions and guide later optimization.

Build, lint, static-analysis and unit-only jobs do not run the application process. They must report application resource measurement as `not applicable`; they must not invent or infer MacVitals CPU/RSS values from the compiler or XCTest host.

## Required runtime evidence

A runtime or physical test is incomplete unless it produces all of the following:

1. `samples.csv` with periodic process samples.
2. `summary.json` from `scripts/collect_runtime_metrics.py`.
3. `resource-summary.json` from `scripts/report_runtime_resources.py`.
4. A normal CI log line beginning with `MACVITALS_RESOURCE_SUMMARY`.
5. A GitHub step summary table when `GITHUB_STEP_SUMMARY` is available.

The summary must include:

- scenario and exact source SHA;
- requested and observed duration;
- sample count and interval;
- CPU mean, p95 and maximum;
- resident-memory mean, p95, peak, first, last and growth;
- thread mean, p95 and maximum when available;
- stable PID/executable identity and whether the process remained alive;
- hardware model, logical CPU count, physical memory, macOS version and architecture in machine-readable evidence.

## Canonical tools

Use the existing process collector:

```bash
PROCESS_NAME=MacVitals \
PROCESS_ID="$app_pid" \
EXPECTED_EXECUTABLE_PATH="$executable" \
OUTPUT_ROOT="$evidence/runtime" \
  bash scripts/collect_runtime_metrics.sh 60 2
```

Then validate and report the single generated summary:

```bash
python3 scripts/report_runtime_resources.py \
  "$summary_path" \
  --scenario idle-status-item \
  --source-sha "$GITHUB_SHA" \
  --output "$evidence/resource-summary.json"
```

The standard packaged smoke already performs this through `scripts/run_ci_runtime_smoke.sh`.

## Measurement rules

- Run on the canonical self-hosted Apple Silicon Mac selector: `[self-hosted, macOS, ARM64]`.
- Record an explicit warm-up period before measurement.
- Pin identity by PID, UID, process start time and expected executable path.
- Use monotonic time for elapsed duration.
- Preserve raw samples; do not publish only a rounded headline.
- CPU values are process `%CPU` as reported by macOS and can exceed 100% when multiple cores are used.
- RSS is resident memory, not total virtual address space.
- Results describe the recorded machine and scenario only; they are not universal product claims.
- Compare like-for-like scenarios, sampling intervals, macOS versions and power states.
- Do not store usernames, home paths, serial numbers, user documents or unrelated process data.

## Minimum scenarios

Every physical candidate should retain at least an idle/status-item baseline. Feature-specific tests should additionally measure the actual exercised state, for example an open overview, detail window, high-frequency sampling or fan-control UI.

Long tests should preserve memory growth and peak RSS so leaks or unbounded caches are visible. Short tests must still collect enough samples to make mean and p95 values meaningful.

## Enforcement

`scripts/validate_runtime_resource_policy.py` examines new or modified runtime workflow/scripts. A changed file that launches MacVitals must invoke the canonical collector and resource reporter. The `Runtime Resource Evidence Policy` workflow runs this gate on self-hosted ARM64.

Tracked by issue #64.
