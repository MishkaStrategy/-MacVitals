#!/bin/bash
set -Eeuo pipefail
IFS=$'\n\t'

[[ $# -eq 4 ]] || {
  printf '%s\n' 'usage: run_single_clock_wakeup_ab.sh <product-root> <derived-data> <evidence-dir> <probe>' >&2
  exit 64
}

PRODUCT_ROOT="$1"
DERIVED_DATA="$2"
EVIDENCE_DIR="$3"
PROBE="$4"
PRODUCT_SHA="${PRODUCT_SHA:?PRODUCT_SHA is required}"

TEST_PID=""
RESOURCE_PID=""
OWNED_PID=""
EXPECTED_EXECUTABLE=""

fail() {
  printf 'single-clock-wakeup-ab: %s\n' "$*" >&2
  exit 1
}

command_for_pid() {
  ps -p "$1" -o command= 2>/dev/null || true
}

exact_pid_is_owned() {
  local pid="$1" executable="$2" command_line
  [[ "${pid}" =~ ^[0-9]+$ && -n "${executable}" ]] || return 1
  kill -0 "${pid}" 2>/dev/null || return 1
  command_line="$(command_for_pid "${pid}")"
  [[ "${command_line}" == "${executable}" || "${command_line}" == "${executable} "* ]]
}

terminate_exact_pid() {
  local pid="$1" executable="$2" attempt
  [[ -n "${pid}" ]] || return 0
  exact_pid_is_owned "${pid}" "${executable}" || return 0
  kill -TERM "${pid}" 2>/dev/null || true
  for attempt in {1..50}; do
    exact_pid_is_owned "${pid}" "${executable}" || return 0
    sleep 0.1
  done
  if exact_pid_is_owned "${pid}" "${executable}"; then
    kill -KILL "${pid}" 2>/dev/null || true
  fi
  for attempt in {1..20}; do
    exact_pid_is_owned "${pid}" "${executable}" || return 0
    sleep 0.1
  done
  return 1
}

fail_on_existing_macvitals() {
  local pid
  if pgrep -x MacVitals >/dev/null 2>&1; then
    printf '%s\n' 'Existing MacVitals process detected; single-clock A/B fails closed and will not terminate it:' >&2
    while IFS= read -r pid; do
      [[ "${pid}" =~ ^[0-9]+$ ]] || continue
      ps -p "${pid}" -o pid=,command= >&2 || true
    done < <(pgrep -x MacVitals 2>/dev/null || true)
    return 1
  fi
}

cleanup_iteration() {
  set +e
  if [[ -n "${RESOURCE_PID}" ]] && kill -0 "${RESOURCE_PID}" 2>/dev/null; then
    kill -TERM "${RESOURCE_PID}" 2>/dev/null || true
    wait "${RESOURCE_PID}" 2>/dev/null || true
  fi
  RESOURCE_PID=""
  if [[ -n "${TEST_PID}" ]] && kill -0 "${TEST_PID}" 2>/dev/null; then
    kill -TERM "${TEST_PID}" 2>/dev/null || true
    wait "${TEST_PID}" 2>/dev/null || true
  fi
  TEST_PID=""
  terminate_exact_pid "${OWNED_PID}" "${EXPECTED_EXECUTABLE}" || true
  OWNED_PID=""
  EXPECTED_EXECUTABLE=""
  set -e
}

cleanup_all() {
  local status="$?"
  trap - EXIT HUP INT TERM
  cleanup_iteration
  exit "${status}"
}
trap cleanup_all EXIT HUP INT TERM

find_owned_pid() {
  local executable="$1" found="" count=0 pid command_line
  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    command_line="$(command_for_pid "${pid}")"
    if [[ "${command_line}" == "${executable}" || "${command_line}" == "${executable} "* ]]; then
      found="${pid}"
      count=$((count + 1))
    elif [[ -n "${command_line}" ]]; then
      printf 'Foreign MacVitals process appeared and will not be terminated: pid=%s command=%s\n' "${pid}" "${command_line}" >&2
      return 2
    fi
  done < <(pgrep -x MacVitals 2>/dev/null || true)
  [[ ${count} -le 1 ]] || return 3
  [[ ${count} -eq 1 ]] || return 1
  printf '%s\n' "${found}"
}

prepare_source() {
  local marker_root="${EVIDENCE_DIR}/markers"
  (
    cd "${PRODUCT_ROOT}"
    python3 scripts/materialize_app_icon.py
    cp project.yml single-clock-wakeup-project.yml
    cat >> single-clock-wakeup-project.yml <<YAML
  MacVitalsSingleClockWakeupAB:
    build:
      targets:
        MacVitals: all
        MacVitalsTests: [test]
    test:
      gatherCoverageData: false
      language: en
      region: US
      targets:
        - MacVitalsTests
      environmentVariables:
        MACVITALS_WAKEUP_AB_READY_FILE: "${marker_root}/ready.txt"
        MACVITALS_WAKEUP_AB_COMPLETE_FILE: "${marker_root}/complete.txt"
        MACVITALS_WAKEUP_AB_TASK_POWER_FILE: "${marker_root}/task-power.json"
YAML
    xcodegen generate --spec single-clock-wakeup-project.yml
    if ! xcodebuild \
      -project MacVitals.xcodeproj \
      -scheme MacVitalsSingleClockWakeupAB \
      -destination 'platform=macOS' \
      -derivedDataPath "${DERIVED_DATA}" \
      ARCHS=arm64 \
      ONLY_ACTIVE_ARCH=YES \
      CODE_SIGNING_ALLOWED=NO \
      build-for-testing \
      > "${EVIDENCE_DIR}/build.log" 2>&1; then
      tail -n 300 "${EVIDENCE_DIR}/build.log" >&2 || true
      return 1
    fi
    test -x "${DERIVED_DATA}/Build/Products/Debug/MacVitals.app/Contents/MacOS/MacVitals"
  )
}

run_iteration() {
  local label="$1" test_method="$2" iteration="$3"
  local marker_root="${EVIDENCE_DIR}/markers"
  local ready="${marker_root}/ready.txt"
  local complete="${marker_root}/complete.txt"
  local task_power_marker="${marker_root}/task-power.json"
  local run_root="${EVIDENCE_DIR}/${label}/run-${iteration}"
  local runtime_root="${run_root}/runtime"
  local test_log="${run_root}/test.log"
  local resource_log="${run_root}/resource-collector.log"
  local wakeup_json="${run_root}/proc-rusage-wakeups.json"
  local task_power_json="${run_root}/task-power-wakeups.json"
  local summary_path summaries summary_count status probe_status resource_status attempt candidate

  cleanup_iteration
  fail_on_existing_macvitals || fail "foreign MacVitals blocks ${label} run ${iteration}"
  rm -f -- "${ready}" "${complete}" "${task_power_marker}"
  mkdir -p "${run_root}" "${runtime_root}" "${marker_root}"
  EXPECTED_EXECUTABLE="${DERIVED_DATA}/Build/Products/Debug/MacVitals.app/Contents/MacOS/MacVitals"
  test -x "${EXPECTED_EXECUTABLE}" || fail "missing product executable"

  (
    cd "${PRODUCT_ROOT}"
    xcodebuild \
      -project MacVitals.xcodeproj \
      -scheme MacVitalsSingleClockWakeupAB \
      -destination 'platform=macOS' \
      -derivedDataPath "${DERIVED_DATA}" \
      ARCHS=arm64 \
      ONLY_ACTIVE_ARCH=YES \
      CODE_SIGNING_ALLOWED=NO \
      test-without-building \
      "-only-testing:MacVitalsTests/ProcessWakeupSingleClockValidationTests/${test_method}"
  ) > "${test_log}" 2>&1 &
  TEST_PID=$!

  for attempt in {1..240}; do
    if [[ -f "${ready}" ]]; then
      set +e
      candidate="$(find_owned_pid "${EXPECTED_EXECUTABLE}")"
      status=$?
      set -e
      if [[ ${status} -eq 0 && -n "${candidate}" ]]; then
        OWNED_PID="${candidate}"
        break
      fi
      if [[ ${status} -eq 2 || ${status} -eq 3 ]]; then
        fail "unsafe MacVitals process state during ${label} run ${iteration}"
      fi
    fi
    if ! kill -0 "${TEST_PID}" 2>/dev/null; then
      break
    fi
    sleep 0.25
  done
  if [[ ! -f "${ready}" || -z "${OWNED_PID}" ]]; then
    tail -n 250 "${test_log}" >&2 || true
    fail "${label} run ${iteration} did not become ready"
  fi
  exact_pid_is_owned "${OWNED_PID}" "${EXPECTED_EXECUTABLE}" || fail "${label} process identity changed before measurement"

  PROCESS_ID="${OWNED_PID}" \
  EXPECTED_EXECUTABLE_PATH="${EXPECTED_EXECUTABLE}" \
  OUTPUT_ROOT="${runtime_root}" \
    bash "${PRODUCT_ROOT}/scripts/collect_runtime_metrics.sh" 60 2 \
    > "${resource_log}" 2>&1 &
  RESOURCE_PID=$!

  set +e
  "${PROBE}" "${OWNED_PID}" 60 > "${wakeup_json}"
  probe_status=$?
  wait "${RESOURCE_PID}"
  resource_status=$?
  set -e
  RESOURCE_PID=""
  [[ ${probe_status} -eq 0 ]] || fail "external wakeup probe failed in ${label} run ${iteration}"
  if [[ ${resource_status} -ne 0 ]]; then
    cat "${resource_log}" >&2 || true
    fail "resource collector failed in ${label} run ${iteration}"
  fi
  exact_pid_is_owned "${OWNED_PID}" "${EXPECTED_EXECUTABLE}" || fail "${label} process identity changed after measurement"

  set +e
  wait "${TEST_PID}"
  status=$?
  set -e
  TEST_PID=""
  if [[ ${status} -ne 0 ]]; then
    tail -n 300 "${test_log}" >&2 || true
    fail "${label} XCTest failed in run ${iteration}"
  fi
  test -f "${complete}" || fail "${label} completion marker missing in run ${iteration}"
  test -f "${task_power_marker}" || fail "${label} TASK_POWER_INFO evidence missing in run ${iteration}"
  cp "${task_power_marker}" "${task_power_json}"
  grep -Eq '\*\* TEST( EXECUTE)? SUCCEEDED \*\*' "${test_log}" || fail "${label} Xcode success marker missing"

  summaries="$(find "${runtime_root}" -mindepth 2 -maxdepth 2 -type f -name summary.json -print)"
  summary_count="$(printf '%s\n' "${summaries}" | awk 'NF { count += 1 } END { print count + 0 }')"
  [[ "${summary_count}" == "1" ]] || fail "${label} run ${iteration} expected one runtime summary"
  summary_path="$(printf '%s\n' "${summaries}" | awk 'NF { print; exit }')"
  python3 "${PRODUCT_ROOT}/scripts/report_runtime_resources.py" \
    "${summary_path}" \
    --scenario "single-clock-wakeup-${label}-run-${iteration}" \
    --source-sha "${PRODUCT_SHA}" \
    --output "${run_root}/resource-summary.json" \
    > "${run_root}/resource-summary.txt"

  python3 - "${wakeup_json}" "${task_power_json}" "${run_root}/resource-summary.json" "${PRODUCT_SHA}" <<'PY'
import json
import math
import sys
from pathlib import Path
proc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
task = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
resources = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
expected_sha = sys.argv[4]
if proc.get("schemaVersion") != 1 or float(proc.get("durationSeconds", 0)) < 59:
    raise SystemExit("proc wakeup observation is too short")
if task.get("schemaVersion") != 1 or float(task.get("durationSeconds", 0)) < 59:
    raise SystemExit("TASK_POWER_INFO observation is too short")
for payload, keys in (
    (proc, ("packageIdleWakeupsPerSecond", "interruptWakeupsPerSecond")),
    (task, (
        "interruptWakeupsPerSecond",
        "platformIdleWakeupsPerSecond",
        "timerWakeupsBin1PerSecond",
        "timerWakeupsBin2PerSecond",
        "totalTimerWakeupsPerSecond",
    )),
):
    for key in keys:
        value = payload.get(key)
        if not isinstance(value, (int, float)) or not math.isfinite(float(value)) or float(value) < 0:
            raise SystemExit(f"invalid wakeup metric: {key}")
if resources.get("sourceSha") != expected_sha:
    raise SystemExit("resource source SHA mismatch")
measurement = resources.get("measurement") or {}
if int(measurement.get("sampleCount", 0)) < 30 or float(measurement.get("durationSeconds", 0)) < 55:
    raise SystemExit("resource observation is incomplete")
PY

  terminate_exact_pid "${OWNED_PID}" "${EXPECTED_EXECUTABLE}" || fail "could not safely terminate ${label} run ${iteration}"
  OWNED_PID=""
  EXPECTED_EXECUTABLE=""
  fail_on_existing_macvitals || fail "MacVitals remained after ${label} run ${iteration}"
}

[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || fail "native Apple Silicon macOS is required"
[[ -x "${PROBE}" ]] || fail "wakeup probe is missing"
git -C "${PRODUCT_ROOT}" merge-base --is-ancestor "${PRODUCT_SHA}" HEAD || \
  fail "validation head does not descend from product SHA"
git -C "${PRODUCT_ROOT}" diff --quiet "${PRODUCT_SHA}" HEAD -- MacVitals project.yml MacVitalsUITests || \
  fail "validation branch modifies product source or project contracts"

rm -rf -- "${DERIVED_DATA}" "${EVIDENCE_DIR}"
mkdir -p "${EVIDENCE_DIR}/legacy" "${EVIDENCE_DIR}/single-clock" "${EVIDENCE_DIR}/markers"
prepare_source

run_iteration legacy testLegacyIndependentProcessConsumersForWakeupMeasurement 1
run_iteration single-clock testSingleClockProcessConsumersForWakeupMeasurement 1
run_iteration single-clock testSingleClockProcessConsumersForWakeupMeasurement 2
run_iteration legacy testLegacyIndependentProcessConsumersForWakeupMeasurement 2
run_iteration legacy testLegacyIndependentProcessConsumersForWakeupMeasurement 3
run_iteration single-clock testSingleClockProcessConsumersForWakeupMeasurement 3

printf '%s\n' 'single-clock-wakeup-ab=collected'
