#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_HELPER="${ROOT_DIR}/scripts/physical_runtime_lock.sh"
[[ -f "${LOCK_HELPER}" && ! -L "${LOCK_HELPER}" ]] || {
  echo "Physical runtime lock helper is missing or unsafe: ${LOCK_HELPER}" >&2
  exit 1
}
# shellcheck source=physical_runtime_lock.sh
source "${LOCK_HELPER}"

DOMAIN=""
PREFS_BACKUP=""
PREFS_CAPTURED=0
PREFS_EXISTED=0
TEST_PID=""

fail() {
  echo "long-baseline: $*" >&2
  exit 1
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
  if kill -0 "${pid}" 2>/dev/null; then
    echo "long-baseline: test process ${pid} could not be reaped" >&2
    return 1
  fi
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

restore_preferences() {
  local restore_status=0
  local lock_status=0

  cleanup_process || restore_status=$?

  if [[ "${PREFS_CAPTURED}" == "1" ]]; then
    if [[ "${PREFS_EXISTED}" == "1" && -s "${PREFS_BACKUP}" ]]; then
      defaults import "${DOMAIN}" "${PREFS_BACKUP}" >/dev/null || restore_status=$?
    else
      defaults delete "${DOMAIN}" >/dev/null 2>&1 || true
    fi
    killall cfprefsd >/dev/null 2>&1 || true
    PREFS_CAPTURED=0
  fi

  # Keep the host lock until the application is gone and preferences are fully
  # restored, so the next physical job cannot observe an intermediate state.
  physical_runtime_lock_release || lock_status=$?
  if [[ "${restore_status}" == "0" && "${lock_status}" != "0" ]]; then
    restore_status="${lock_status}"
  fi
  return "${restore_status}"
}

handle_signal() {
  local exit_status="$1"
  restore_preferences || true
  trap - EXIT INT TERM
  exit "${exit_status}"
}

long_baseline_cleanup_self_test() {
  local temp_root fake_bin defaults_log backup original_path
  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/macvitals-long-baseline-cleanup-test.XXXXXX")"
  fake_bin="${temp_root}/bin"
  defaults_log="${temp_root}/defaults.log"
  backup="${temp_root}/preferences-before.plist"
  original_path="${PATH}"

  cleanup_self_test() {
    PATH="${original_path}"
    export PATH
    physical_runtime_lock_release >/dev/null 2>&1 || true
    rm -rf -- "${temp_root}"
  }
  trap cleanup_self_test EXIT INT TERM

  mkdir -p "${fake_bin}"
  printf 'fixture\n' > "${backup}"
  : > "${defaults_log}"

  cat > "${fake_bin}/defaults" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${DEFAULTS_LOG:?}"
if [[ -n "${EXPECTED_LOCK_DIR:-}" && ! -d "${EXPECTED_LOCK_DIR}" ]]; then
  printf '%s\n' 'lock-missing-during-defaults' >> "${DEFAULTS_LOG}"
  exit 8
fi
if [[ "${FAIL_DEFAULTS_IMPORT:-0}" == "1" && "${1:-}" == "import" ]]; then
  exit 9
fi
SH
  cat > "${fake_bin}/killall" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod 0700 "${fake_bin}/defaults" "${fake_bin}/killall"

  PATH="${fake_bin}:${PATH}"
  export PATH
  export DEFAULTS_LOG="${defaults_log}"
  export MACVITALS_PHYSICAL_LOCK_DIR="${temp_root}/runtime.lock"
  export MACVITALS_PHYSICAL_LOCK_TIMEOUT_SECONDS=2
  export MACVITALS_PHYSICAL_LOCK_POLL_SECONDS=0.1
  export MACVITALS_PHYSICAL_LOCK_STALE_GRACE_SECONDS=0
  export EXPECTED_LOCK_DIR="${MACVITALS_PHYSICAL_LOCK_DIR}"

  DOMAIN="self.test.domain"
  PREFS_BACKUP="${backup}"
  TEST_PID=""

  # An error before preference capture must release the lock without touching
  # the user's defaults domain.
  : > "${defaults_log}"
  PREFS_CAPTURED=0
  PREFS_EXISTED=0
  MACVITALS_PHYSICAL_LOCK_HELD=0
  physical_runtime_lock_acquire >/dev/null
  restore_preferences
  [[ ! -e "${MACVITALS_PHYSICAL_LOCK_DIR}" && ! -s "${defaults_log}" ]] || {
    echo 'Early cleanup self-test failed' >&2
    return 1
  }

  # Existing preferences must be imported while the lock is still held.
  : > "${defaults_log}"
  PREFS_CAPTURED=1
  PREFS_EXISTED=1
  physical_runtime_lock_acquire >/dev/null
  restore_preferences
  grep -Fq "import ${DOMAIN} ${PREFS_BACKUP}" "${defaults_log}"
  ! grep -Fq 'lock-missing-during-defaults' "${defaults_log}"
  [[ ! -e "${MACVITALS_PHYSICAL_LOCK_DIR}" && "${PREFS_CAPTURED}" == "0" ]]

  # A previously absent domain must be deleted while the lock is still held.
  : > "${defaults_log}"
  PREFS_CAPTURED=1
  PREFS_EXISTED=0
  physical_runtime_lock_acquire >/dev/null
  restore_preferences
  grep -Fq "delete ${DOMAIN}" "${defaults_log}"
  ! grep -Fq 'lock-missing-during-defaults' "${defaults_log}"
  [[ ! -e "${MACVITALS_PHYSICAL_LOCK_DIR}" && "${PREFS_CAPTURED}" == "0" ]]

  # Import failure must propagate as failure but still release the lock and
  # leave cleanup idempotent for the EXIT trap.
  : > "${defaults_log}"
  PREFS_CAPTURED=1
  PREFS_EXISTED=1
  export FAIL_DEFAULTS_IMPORT=1
  physical_runtime_lock_acquire >/dev/null
  if restore_preferences; then
    echo 'Failing preferences import unexpectedly passed' >&2
    return 1
  fi
  unset FAIL_DEFAULTS_IMPORT
  [[ ! -e "${MACVITALS_PHYSICAL_LOCK_DIR}" && "${PREFS_CAPTURED}" == "0" ]]

  trap - EXIT INT TERM
  cleanup_self_test
  echo 'Long-baseline cleanup self-test passed'
}

if [[ "${1:-}" == "--self-test" ]]; then
  long_baseline_cleanup_self_test
  exit 0
fi

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

mkdir -p "${OUTPUT_ROOT}"

trap 'restore_preferences || true' EXIT
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM

[[ "${SOURCE_SHA}" =~ ^[0-9a-f]{40}$ ]] || fail "source SHA is not a full lowercase SHA-1"
[[ -x "${EXECUTABLE}" ]] || fail "MacVitals executable is missing"
[[ "$(uname -m)" == "arm64" ]] || fail "runner is not arm64"
file "${EXECUTABLE}" | grep -q 'arm64' || fail "MacVitals executable is not arm64"

POWER_STATE="$(pmset -g batt | head -n 1)"
[[ "${POWER_STATE}" == *"AC Power"* ]] || fail "runner is not connected to AC power: ${POWER_STATE}"

physical_runtime_lock_acquire || fail "could not acquire physical runtime lock"

if pgrep -x MacVitals >/dev/null 2>&1; then
  fail "a MacVitals process was already running before the test"
fi

if defaults export "${DOMAIN}" "${PREFS_BACKUP}" >/dev/null 2>&1; then
  PREFS_EXISTED=1
fi
PREFS_CAPTURED=1

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

if ! restore_preferences; then
  trap - EXIT INT TERM
  fail "failed to restore preferences or release physical runtime lock"
fi
trap - EXIT INT TERM
