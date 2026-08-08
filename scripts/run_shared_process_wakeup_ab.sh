#!/bin/bash
set -Eeuo pipefail
IFS=$'\n\t'

[[ $# -eq 7 ]] || {
  printf '%s\n' 'usage: run_shared_process_wakeup_ab.sh <baseline-root> <baseline-derived> <product-root> <product-derived> <evidence-dir> <probe> <validation-test>' >&2
  exit 64
}

BASELINE_ROOT="$1"
BASELINE_DERIVED="$2"
PRODUCT_ROOT="$3"
PRODUCT_DERIVED="$4"
EVIDENCE_DIR="$5"
PROBE="$6"
VALIDATION_TEST="$7"
BASELINE_SHA="${BASELINE_SHA:?BASELINE_SHA is required}"
PRODUCT_SHA="${PRODUCT_SHA:?PRODUCT_SHA is required}"

TEST_PID=""
RESOURCE_PID=""
OWNED_PID=""
EXPECTED_EXECUTABLE=""

fail() {
  printf 'shared-process-wakeup-ab: %s\n' "$*" >&2
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
    printf '%s\n' 'Existing MacVitals process detected; wakeup A/B fails closed and will not terminate it:' >&2
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
  git -C "${PRODUCT_ROOT}" worktree remove --force "${BASELINE_ROOT}" >/dev/null 2>&1 || true
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
  local source_root="$1" derived_data="$2" marker_root="$3"
  (
    cd "${source_root}"
    python3 scripts/materialize_app_icon.py
    cp project.yml wakeup-ab-project.yml
    cat >> wakeup-ab-project.yml <<YAML
  MacVitalsWakeupAB:
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
YAML
    xcodegen generate --spec wakeup-ab-project.yml
    xcodebuild \
      -project MacVitals.xcodeproj \
      -scheme MacVitalsWakeupAB \
      -destination 'platform=macOS' \
      -derivedDataPath "${derived_data}" \
      ARCHS=arm64 \
      ONLY_ACTIVE_ARCH=YES \
      CODE_SIGNING_ALLOWED=NO \
      build-for-testing \
      > wakeup-ab-build.log 2>&1
    test -x "${derived_data}/Build/Products/Debug/MacVitals.app/Contents/MacOS/MacVitals"
  )
}

run_iteration() {
  local label="$1" source_root="$2" derived_data="$3" source_sha="$4" iteration="$5"
  local marker_root="${EVIDENCE_DIR}/${label}"
  local ready="${marker_root}/ready.txt"
  local complete="${marker_root}/complete.txt"
  local run_root="${marker_root}/run-${iteration}"
  local runtime_root="${run_root}/runtime"
  local test_log="${run_root}/test.log"
  local resource_log="${run_root}/resource-collector.log"
  local wakeup_json="${run_root}/wakeups.json"
  local summary_path summaries summary_count status probe_status resource_status attempt candidate

  cleanup_iteration
  fail_on_existing_macvitals || fail "foreign MacVitals blocks ${label} run ${iteration}"
  rm -f -- "${ready}" "${complete}"
  mkdir -p "${run_root}" "${runtime_root}"
  EXPECTED_EXECUTABLE="${derived_data}/Build/Products/Debug/MacVitals.app/Contents/MacOS/MacVitals"
  test -x "${EXPECTED_EXECUTABLE}" || fail "missing ${label} executable"

  (
    cd "${source_root}"
    xcodebuild \
      -project MacVitals.xcodeproj \
      -scheme MacVitalsWakeupAB \
      -destination 'platform=macOS' \
      -derivedDataPath "${derived_data}" \
      ARCHS=arm64 \
      ONLY_ACTIVE_ARCH=YES \
      CODE_SIGNING_ALLOWED=NO \
      test-without-building \
      -only-testing:MacVitalsTests/ProcessWakeupABTests/testTwoConcurrentProcessConsumersForWakeupMeasurement
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
  [[ ${probe_status} -eq 0 ]] || fail "wakeup probe failed in ${label} run ${iteration}"
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
  grep -Eq '\*\* TEST( EXECUTE)? SUCCEEDED \*\*' "${test_log}" || fail "${label} Xcode success marker missing"

  summaries="$(find "${runtime_root}" -mindepth 2 -maxdepth 2 -type f -name summary.json -print)"
  summary_count="$(printf '%s\n' "${summaries}" | awk 'NF { count += 1 } END { print count + 0 }')"
  [[ "${summary_count}" == "1" ]] || fail "${label} run ${iteration} expected one runtime summary"
  summary_path="$(printf '%s\n' "${summaries}" | awk 'NF { print; exit }')"
  python3 "${PRODUCT_ROOT}/scripts/report_runtime_resources.py" \
    "${summary_path}" \
    --scenario "wakeup-ab-${label}-run-${iteration}" \
    --source-sha "${source_sha}" \
    --output "${run_root}/resource-summary.json" \
    > "${run_root}/resource-summary.txt"

  python3 - "${wakeup_json}" "${run_root}/resource-summary.json" "${source_sha}" "${label}" "${iteration}" <<'PY'
import json
import math
import sys
from pathlib import Path
wakeups = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
resources = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
expected_sha, label, iteration = sys.argv[3], sys.argv[4], int(sys.argv[5])
if wakeups.get("schemaVersion") != 1 or float(wakeups.get("durationSeconds", 0)) < 59:
    raise SystemExit("wakeup observation is too short")
for key in ("packageIdleWakeupsPerSecond", "interruptWakeupsPerSecond"):
    value = wakeups.get(key)
    if not isinstance(value, (int, float)) or not math.isfinite(float(value)) or float(value) < 0:
        raise SystemExit(f"invalid wakeup metric: {key}")
if resources.get("sourceSha") != expected_sha:
    raise SystemExit("resource source SHA mismatch")
measurement = resources.get("measurement") or {}
if int(measurement.get("sampleCount", 0)) < 30 or float(measurement.get("durationSeconds", 0)) < 55:
    raise SystemExit("resource observation is incomplete")
print(json.dumps({
    "label": label,
    "iteration": iteration,
    "sourceSha": expected_sha,
    "packageIdleWakeupsPerSecond": wakeups["packageIdleWakeupsPerSecond"],
    "interruptWakeupsPerSecond": wakeups["interruptWakeupsPerSecond"],
    "cpuMeanPercent": (measurement.get("cpuPercent") or {}).get("mean"),
}, sort_keys=True))
PY

  terminate_exact_pid "${OWNED_PID}" "${EXPECTED_EXECUTABLE}" || fail "could not safely terminate ${label} run ${iteration}"
  OWNED_PID=""
  EXPECTED_EXECUTABLE=""
  fail_on_existing_macvitals || fail "MacVitals remained after ${label} run ${iteration}"
}

[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || fail "native Apple Silicon macOS is required"
[[ -x "${PROBE}" ]] || fail "wakeup probe is missing"
[[ -f "${VALIDATION_TEST}" && ! -L "${VALIDATION_TEST}" ]] || fail "validation test is missing or unsafe"

rm -rf -- "${BASELINE_ROOT}" "${BASELINE_DERIVED}" "${PRODUCT_DERIVED}" "${EVIDENCE_DIR}"
mkdir -p "${EVIDENCE_DIR}/baseline" "${EVIDENCE_DIR}/product"
git -C "${PRODUCT_ROOT}" worktree add --detach "${BASELINE_ROOT}" "${BASELINE_SHA}"
cp "${VALIDATION_TEST}" "${BASELINE_ROOT}/MacVitalsTests/ProcessWakeupABTests.swift"
prepare_source "${BASELINE_ROOT}" "${BASELINE_DERIVED}" "${EVIDENCE_DIR}/baseline"
prepare_source "${PRODUCT_ROOT}" "${PRODUCT_DERIVED}" "${EVIDENCE_DIR}/product"

# Alternate pair order so neither revision always gets the earlier/cooler slot.
run_iteration baseline "${BASELINE_ROOT}" "${BASELINE_DERIVED}" "${BASELINE_SHA}" 1
run_iteration product "${PRODUCT_ROOT}" "${PRODUCT_DERIVED}" "${PRODUCT_SHA}" 1
run_iteration product "${PRODUCT_ROOT}" "${PRODUCT_DERIVED}" "${PRODUCT_SHA}" 2
run_iteration baseline "${BASELINE_ROOT}" "${BASELINE_DERIVED}" "${BASELINE_SHA}" 2
run_iteration baseline "${BASELINE_ROOT}" "${BASELINE_DERIVED}" "${BASELINE_SHA}" 3
run_iteration product "${PRODUCT_ROOT}" "${PRODUCT_DERIVED}" "${PRODUCT_SHA}" 3

printf '%s\n' 'shared-process-wakeup-ab=collected'
