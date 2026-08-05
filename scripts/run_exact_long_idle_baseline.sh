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
RUNNER_IDLE_TIMEOUT_SECONDS="${RUNNER_IDLE_TIMEOUT_SECONDS:-900}"
LOCK_DIR="${MACVITALS_PHYSICAL_LOCK_DIR:-/tmp/macvitals-physical-runtime.lock}"
PREFS_BACKUP="${OUTPUT_ROOT}/preferences-before.plist"
PREFS_EXISTED=0
PREFS_SNAPSHOT_TAKEN=0
LOCK_HELD=0
TEST_PID=""

mkdir -p "${OUTPUT_ROOT}"

fail() {
  echo "long-baseline: $*" >&2
  exit 1
}

acquire_runner_lock() {
  local deadline=$((SECONDS + RUNNER_IDLE_TIMEOUT_SECONDS))
  local owner_pid=""
  local stale_dir=""

  while ! mkdir "${LOCK_DIR}" 2>/dev/null; do
    owner_pid=""
    if [[ -r "${LOCK_DIR}/owner-pid" ]]; then
      read -r owner_pid < "${LOCK_DIR}/owner-pid" || owner_pid=""
    fi

    if [[ "${owner_pid}" =~ ^[0-9]+$ ]] && ! kill -0 "${owner_pid}" 2>/dev/null; then
      stale_dir="${LOCK_DIR}.stale.$$"
      if mv "${LOCK_DIR}" "${stale_dir}" 2>/dev/null; then
        rm -rf "${stale_dir}"
        continue
      fi
    fi

    if ((SECONDS >= deadline)); then
      fail "physical runtime lock remained busy for ${RUNNER_IDLE_TIMEOUT_SECONDS}s"
    fi
    sleep 2
  done

  printf '%s\n' "$$" > "${LOCK_DIR}/owner-pid"
  printf 'source_sha=%s\nstarted_utc=%s\n' \
    "${SOURCE_SHA}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    > "${LOCK_DIR}/owner-metadata"
  LOCK_HELD=1
}

release_runner_lock() {
  local owner_pid=""
  if [[ "${LOCK_HELD}" != "1" ]]; then
    return
  fi

  if [[ -r "${LOCK_DIR}/owner-pid" ]]; then
    read -r owner_pid < "${LOCK_DIR}/owner-pid" || owner_pid=""
  fi
  if [[ "${owner_pid}" == "$$" ]]; then
    rm -rf "${LOCK_DIR}"
  fi
  LOCK_HELD=0
}

cleanup_process() {
  local pid="${TEST_PID}"
  if [[ -z "${pid}" ]]; then
    return
  fi

  if kill -0 "${pid}" 2>/dev/null; then
    kill -TERM "${pid}" 2>/dev/null || true
    for _ in {1..50}; do
      kill -0 "${pid}" 2>/dev/null || break
      sleep 0.1
    done
  fi

  if kill -0 "${pid}" 2>/dev/null; then
    kill -KILL "${pid}" 2>/dev/null || true
  fi

  # The app is a direct child of this harness. Reap it before checking the
  # global process table so a short-lived zombie cannot fail the next-run gate.
  wait "${pid}" 2>/dev/null || true
  for _ in {1..50}; do
    kill -0 "${pid}" 2>/dev/null || break
    sleep 0.1
  done
  kill -0 "${pid}" 2>/dev/null && fail "test process ${pid} could not be reaped"
  TEST_PID=""
}

wait_for_no_macvitals() {
  local context="$1"
  for _ in {1..50}; do
    pgrep -x MacVitals >/dev/null 2>&1 || return 0
    sleep 0.1
  done
  fail "MacVitals remained alive ${context}"
}

wait_for_runner_idle() {
  local context="$1"
  local deadline=$((SECONDS + RUNNER_IDLE_TIMEOUT_SECONDS))

  while pgrep -x MacVitals >/dev/null 2>&1; do
    if ((SECONDS >= deadline)); then
      pgrep -flx MacVitals >&2 || true
      fail "runner remained busy ${context} for ${RUNNER_IDLE_TIMEOUT_SECONDS}s"
    fi
    sleep 2
  done
}

restore_preferences() {
  cleanup_process
  if [[ "${PREFS_SNAPSHOT_TAKEN}" == "1" ]]; then
    if [[ "${PREFS_EXISTED}" == "1" && -s "${PREFS_BACKUP}" ]]; then
      defaults import "${DOMAIN}" "${PREFS_BACKUP}" >/dev/null
    else
      defaults delete "${DOMAIN}" >/dev/null 2>&1 || true
    fi
    killall cfprefsd >/dev/null 2>&1 || true
  fi
  release_runner_lock
}
trap restore_preferences EXIT INT TERM

[[ "${SOURCE_SHA}" =~ ^[0-9a-f]{40}$ ]] || fail "source SHA is not a full lowercase SHA-1"
[[ -x "${EXECUTABLE}" ]] || fail "MacVitals executable is missing"
[[ "$(uname -m)" == "arm64" ]] || fail "runner is not arm64"
file "${EXECUTABLE}" | grep -q 'arm64' || fail "MacVitals executable is not arm64"
[[ "${RUNNER_IDLE_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] || fail "runner idle timeout is not an integer"
((RUNNER_IDLE_TIMEOUT_SECONDS > 0)) || fail "runner idle timeout must be positive"

POWER_STATE="$(pmset -g batt | head -n 1)"
[[ "${POWER_STATE}" == *"AC Power"* ]] || fail "runner is not connected to AC power: ${POWER_STATE}"

acquire_runner_lock
wait_for_runner_idle "before the test"

rm -f "${PREFS_BACKUP}"
if defaults export "${DOMAIN}" "${PREFS_BACKUP}" >/dev/null 2>&1; then
  PREFS_EXISTED=1
fi
PREFS_SNAPSHOT_TAKEN=1

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
  "runCount": ${RUN_COUNT},
  "runnerIdleTimeoutSeconds": ${RUNNER_IDLE_TIMEOUT_SECONDS}
}
EOF

for run_number in $(seq 1 "${RUN_COUNT}"); do
  RUN_ROOT="${OUTPUT_ROOT}/run-${run_number}"
  PROCESS_ROOT="${RUN_ROOT}/process"
  PROVIDER_JSONL="${RUN_ROOT}/provider-timings.jsonl"
  PROVIDER_SUMMARY="${RUN_ROOT}/provider-summary.json"
  APP_LOG="${RUN_ROOT}/app.log"
  mkdir -p "${RUN_ROOT}" "${PROCESS_ROOT}"

  wait_for_no_macvitals "before run ${run_number}"

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
  wait_for_no_macvitals "after run ${run_number} cleanup"
  sleep 2
done

python3 - "${OUTPUT_ROOT}" "${RUN_COUNT}" <<'PY'
import json
import statistics
import sys
from pathlib import Path

root = Path(sys.argv[1])
expected_run_count = int(sys.argv[2])
reports = [json.loads(path.read_text()) for path in sorted(root.glob("run-*/resource-summary.json"))]
if len(reports) != expected_run_count:
    raise SystemExit(
        f"expected {expected_run_count} resource reports, found {len(reports)}")

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
