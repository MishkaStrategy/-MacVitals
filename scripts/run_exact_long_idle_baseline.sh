#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:?usage: run_exact_long_idle_baseline.sh APP_PATH SOURCE_SHA OUTPUT_ROOT}"
SOURCE_SHA="${2:?usage: run_exact_long_idle_baseline.sh APP_PATH SOURCE_SHA OUTPUT_ROOT}"
OUTPUT_ROOT="${3:?usage: run_exact_long_idle_baseline.sh APP_PATH SOURCE_SHA OUTPUT_ROOT}"
EXECUTABLE="${APP_PATH}/Contents/MacOS/MacVitals"
DOMAIN="com.mishkacher.MacVitals"
WARMUP_SECONDS="${WARMUP_SECONDS:-300}"
MEASURE_SECONDS="${MEASURE_SECONDS:-1800}"
SAMPLE_SECONDS="${SAMPLE_SECONDS:-2}"
RUN_COUNT="${RUN_COUNT:-3}"
PREFS_BACKUP="${OUTPUT_ROOT}/preferences-before.plist"
PREFS_EXISTED=0
TEST_PID=""

mkdir -p "${OUTPUT_ROOT}"

fail() {
  echo "long-baseline: $*" >&2
  exit 1
}

cleanup_process() {
  if [[ -n "${TEST_PID}" ]] && kill -0 "${TEST_PID}" 2>/dev/null; then
    kill -TERM "${TEST_PID}" 2>/dev/null || true
    for _ in {1..50}; do
      kill -0 "${TEST_PID}" 2>/dev/null || break
      sleep 0.1
    done
    kill -KILL "${TEST_PID}" 2>/dev/null || true
  fi
  TEST_PID=""
}

restore_preferences() {
  cleanup_process
  if [[ "${PREFS_EXISTED}" == "1" && -s "${PREFS_BACKUP}" ]]; then
    defaults import "${DOMAIN}" "${PREFS_BACKUP}" >/dev/null
  else
    defaults delete "${DOMAIN}" >/dev/null 2>&1 || true
  fi
  killall cfprefsd >/dev/null 2>&1 || true
}
trap restore_preferences EXIT INT TERM

[[ "${SOURCE_SHA}" =~ ^[0-9a-f]{40}$ ]] || fail "source SHA is not a full lowercase SHA-1"
[[ -x "${EXECUTABLE}" ]] || fail "MacVitals executable is missing"
[[ "$(uname -m)" == "arm64" ]] || fail "runner is not arm64"
file "${EXECUTABLE}" | grep -q 'arm64' || fail "MacVitals executable is not arm64"

POWER_STATE="$(pmset -g batt | head -n 1)"
[[ "${POWER_STATE}" == *"AC Power"* ]] || fail "runner is not connected to AC power: ${POWER_STATE}"

if pgrep -x MacVitals >/dev/null 2>&1; then
  fail "a MacVitals process was already running before the test"
fi

if defaults export "${DOMAIN}" "${PREFS_BACKUP}" >/dev/null 2>&1; then
  PREFS_EXISTED=1
fi

DUAL_CONFIGURATION_HEX="$(python3 - <<'PY'
import json
payload = {
    "schemaVersion": 4,
    "configuration": {
        "metric": "cpu",
        "secondaryMetric": "temperature",
        "showValueText": True,
        "showSensorName": True,
        "colorMode": "automatic",
        "accent": "cyan",
        "lineThickness": 2.5,
        "horizontalExtension": 72.0,
        "trackOpacity": 0.18,
        "glowIntensity": 0.62,
        "warningThreshold": 75.0,
        "criticalThreshold": 90.0,
        "secondaryWarningThreshold": 75.0,
        "secondaryCriticalThreshold": 90.0,
        "animateChanges": True,
        "showOnDisplaysWithoutNotch": False,
    },
}
print(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode().hex())
PY
)"

defaults write "${DOMAIN}" samplingInterval -float 2
defaults write "${DOMAIN}" experimentalNotchHUDEnabled -bool true
defaults write "${DOMAIN}" notchHUDConfiguration.v1 -data "${DUAL_CONFIGURATION_HEX}"
killall cfprefsd >/dev/null 2>&1 || true

cat > "${OUTPUT_ROOT}/scenario.json" <<EOF
{
  "schemaVersion": 1,
  "sourceSha": "${SOURCE_SHA}",
  "powerSource": "AC",
  "samplingIntervalSeconds": 2,
  "hudMode": "dual-contour",
  "overviewOpen": false,
  "detailWindowsOpen": false,
  "warmupSecondsPerRun": ${WARMUP_SECONDS},
  "measurementSecondsPerRun": ${MEASURE_SECONDS},
  "collectorIntervalSeconds": ${SAMPLE_SECONDS},
  "runCount": ${RUN_COUNT}
}
EOF

for run_number in $(seq 1 "${RUN_COUNT}"); do
  RUN_ROOT="${OUTPUT_ROOT}/run-${run_number}"
  PROCESS_ROOT="${RUN_ROOT}/process"
  PROVIDER_JSONL="${RUN_ROOT}/provider-timings.jsonl"
  PROVIDER_SUMMARY="${RUN_ROOT}/provider-summary.json"
  APP_LOG="${RUN_ROOT}/app.log"
  mkdir -p "${RUN_ROOT}" "${PROCESS_ROOT}"

  if pgrep -x MacVitals >/dev/null 2>&1; then
    fail "MacVitals was unexpectedly running before run ${run_number}"
  fi

  MACVITALS_PROVIDER_TIMINGS_PATH="${PROVIDER_JSONL}" \
    "${EXECUTABLE}" >"${APP_LOG}" 2>&1 &
  TEST_PID=$!

  sleep 2
  kill -0 "${TEST_PID}" 2>/dev/null || fail "MacVitals exited during launch in run ${run_number}"
  ACTUAL_PID="$(pgrep -x MacVitals || true)"
  [[ "${ACTUAL_PID}" == "${TEST_PID}" ]] || fail "process identity mismatch in run ${run_number}"

  sleep "${WARMUP_SECONDS}"
  kill -0 "${TEST_PID}" 2>/dev/null || fail "MacVitals exited during warm-up in run ${run_number}"

  PROCESS_ID="${TEST_PID}" \
  EXPECTED_EXECUTABLE_PATH="${EXECUTABLE}" \
  OUTPUT_ROOT="${PROCESS_ROOT}" \
    bash "${ROOT_DIR}/scripts/collect_runtime_metrics.sh" \
      "${MEASURE_SECONDS}" "${SAMPLE_SECONDS}"

  SUMMARY_PATH="$(find "${PROCESS_ROOT}" -name summary.json -type f -print -quit)"
  [[ -n "${SUMMARY_PATH}" ]] || fail "summary.json is missing for run ${run_number}"

  python3 "${ROOT_DIR}/scripts/report_runtime_resources.py" \
    "${SUMMARY_PATH}" \
    --scenario "ac-idle-dual-2s-run-${run_number}" \
    --source-sha "${SOURCE_SHA}" \
    --output "${RUN_ROOT}/resource-summary.json"

  [[ -s "${PROVIDER_JSONL}" ]] || fail "provider timing JSONL is missing for run ${run_number}"
  python3 "${ROOT_DIR}/scripts/summarize_provider_timings.py" \
    --input "${PROVIDER_JSONL}" \
    --output "${PROVIDER_SUMMARY}" \
    --configured-interval 2

  cleanup_process
  pgrep -x MacVitals >/dev/null 2>&1 && fail "MacVitals remained alive after run ${run_number} cleanup"
  sleep 2
done

python3 - "${OUTPUT_ROOT}" <<'PY'
import json
import statistics
import sys
from pathlib import Path

root = Path(sys.argv[1])
reports = [json.loads(path.read_text()) for path in sorted(root.glob("run-*/resource-summary.json"))]
if len(reports) < 1:
    raise SystemExit("no resource reports")

def values(*keys):
    result = []
    for report in reports:
        value = report
        for key in keys:
            value = value[key]
        result.append(float(value))
    return result

aggregate = {
    "schemaVersion": 1,
    "runCount": len(reports),
    "sourceSha": reports[0]["sourceSha"],
    "median": {
        "cpuMeanPercent": statistics.median(values("measurement", "cpuPercent", "mean")),
        "cpuP95Percent": statistics.median(values("measurement", "cpuPercent", "p95")),
        "rssMeanMiB": statistics.median(values("measurement", "residentMemoryMiB", "mean")),
        "rssGrowthMiB": statistics.median(values("measurement", "residentMemoryMiB", "growth")),
    },
    "runs": reports,
}
(root / "aggregate-summary.json").write_text(json.dumps(aggregate, indent=2, sort_keys=True) + "\n")
print("MACVITALS_LONG_BASELINE_SUMMARY " + " ".join([
    f"source_sha={aggregate['sourceSha']}",
    f"runs={aggregate['runCount']}",
    f"cpu_mean_median_pct={aggregate['median']['cpuMeanPercent']:.3f}",
    f"cpu_p95_median_pct={aggregate['median']['cpuP95Percent']:.3f}",
    f"rss_mean_median_mib={aggregate['median']['rssMeanMiB']:.3f}",
    f"rss_growth_median_mib={aggregate['median']['rssGrowthMiB']:.3f}",
]))
PY

restore_preferences
trap - EXIT INT TERM
