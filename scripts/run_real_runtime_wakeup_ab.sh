#!/bin/bash
set -Eeuo pipefail
IFS=$'\n\t'

[[ $# -eq 3 ]] || {
  printf '%s\n' 'usage: run_real_runtime_wakeup_ab.sh <validation-root> <evidence-dir> <probe>' >&2
  exit 64
}

VALIDATION_ROOT="$1"
EVIDENCE_DIR="$2"
PROBE="$3"
BASELINE_SHA="${BASELINE_SHA:?BASELINE_SHA is required}"
CANDIDATE_SHA="${CANDIDATE_SHA:?CANDIDATE_SHA is required}"
VALIDATION_SHA="${VALIDATION_SHA:?VALIDATION_SHA is required}"
WORK_ROOT="${RUNNER_TEMP:-/tmp}/macvitals-real-runtime-ab-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}"
UI_SOURCE="${VALIDATION_ROOT}/MacVitalsUITests/ProcessWakeupRealRuntimeABUITests.swift"

TEST_PID=""
OWNED_PID=""
EXPECTED_EXECUTABLE=""
RESOURCE_PID=""

fail() {
  printf 'real-runtime-wakeup-ab: %s\n' "$*" >&2
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
  local pid="$1" executable="$2"
  [[ -n "${pid}" ]] || return 0
  exact_pid_is_owned "${pid}" "${executable}" || return 0
  kill -TERM "${pid}" 2>/dev/null || true
  for _ in {1..50}; do
    exact_pid_is_owned "${pid}" "${executable}" || return 0
    sleep 0.1
  done
  if exact_pid_is_owned "${pid}" "${executable}"; then
    kill -KILL "${pid}" 2>/dev/null || true
  fi
  for _ in {1..20}; do
    exact_pid_is_owned "${pid}" "${executable}" || return 0
    sleep 0.1
  done
  return 1
}

fail_on_foreign_macvitals() {
  local pid command_line
  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    command_line="$(command_for_pid "${pid}")"
    [[ -n "${command_line}" ]] || continue
    if [[ -n "${OWNED_PID}" && "${pid}" == "${OWNED_PID}" ]] \
      && exact_pid_is_owned "${pid}" "${EXPECTED_EXECUTABLE}"; then
      continue
    fi
    printf 'Foreign MacVitals process detected and will not be terminated: pid=%s command=%s\n' \
      "${pid}" "${command_line}" >&2
    return 1
  done < <(pgrep -x MacVitals 2>/dev/null || true)
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
  git -C "${VALIDATION_ROOT}" worktree remove --force "${WORK_ROOT}/baseline" >/dev/null 2>&1 || true
  git -C "${VALIDATION_ROOT}" worktree remove --force "${WORK_ROOT}/candidate" >/dev/null 2>&1 || true
  rm -rf -- "${WORK_ROOT}"
  exit "${status}"
}
trap cleanup_all EXIT HUP INT TERM

prepare_revision() {
  local label="$1" sha="$2"
  local root="${WORK_ROOT}/${label}"
  local derived="${WORK_ROOT}/DerivedData-${label}"
  local markers="${WORK_ROOT}/markers-${label}"
  mkdir -p "${markers}"

  git -C "${VALIDATION_ROOT}" worktree add --detach "${root}" "${sha}" \
    > "${EVIDENCE_DIR}/${label}-worktree.log" 2>&1
  cp "${UI_SOURCE}" "${root}/MacVitalsUITests/ProcessWakeupRealRuntimeABUITests.swift"

  (
    cd "${root}"
    python3 scripts/materialize_app_icon.py
    cp project.yml real-runtime-ab-project.yml
    cat >> real-runtime-ab-project.yml <<YAML
  MacVitalsRealRuntimeWakeupAB:
    build:
      targets:
        MacVitals: all
        MacVitalsUITests: [test]
    test:
      gatherCoverageData: false
      language: en
      region: US
      targets:
        - MacVitalsUITests
      environmentVariables:
        MACVITALS_REAL_AB_READY_FILE: "${markers}/ready.txt"
        MACVITALS_REAL_AB_STOP_FILE: "${markers}/stop.txt"
        MACVITALS_REAL_AB_COMPLETE_FILE: "${markers}/complete.txt"
YAML
    xcodegen generate --spec real-runtime-ab-project.yml
    rm -rf -- "${derived}"
    set +e
    xcodebuild \
      -project MacVitals.xcodeproj \
      -scheme MacVitalsRealRuntimeWakeupAB \
      -configuration Debug \
      -destination 'platform=macOS' \
      -derivedDataPath "${derived}" \
      ARCHS=arm64 \
      ONLY_ACTIVE_ARCH=YES \
      CODE_SIGNING_ALLOWED=NO \
      build-for-testing \
      > "${EVIDENCE_DIR}/${label}-build.log" 2>&1
    build_status=$?
    set -e
    if [[ ${build_status} -ne 0 ]]; then
      tail -n 300 "${EVIDENCE_DIR}/${label}-build.log" >&2 || true
      exit "${build_status}"
    fi
    test -x "${derived}/Build/Products/Debug/MacVitals.app/Contents/MacOS/MacVitals"
  )
}

run_iteration() {
  local label="$1" revision="$2" iteration="$3"
  local root="${WORK_ROOT}/${revision}"
  local derived="${WORK_ROOT}/DerivedData-${revision}"
  local markers="${WORK_ROOT}/markers-${revision}"
  local ready="${markers}/ready.txt"
  local stop="${markers}/stop.txt"
  local complete="${markers}/complete.txt"
  local run_root="${EVIDENCE_DIR}/${label}/run-${iteration}"
  local runtime_root="${run_root}/runtime"
  local isolated_home="${run_root}/home"
  local test_log="${run_root}/ui-test.log"
  local app_log="${run_root}/app.log"
  local env_log="${run_root}/app-environment.txt"
  local probe_json="${run_root}/proc-rusage-wakeups.json"
  local resource_log="${run_root}/resource-collector.log"
  local summary_path summaries summary_count probe_status resource_status test_status
  local sha

  case "${label}" in
    baseline) sha="${BASELINE_SHA}" ;;
    candidate) sha="${CANDIDATE_SHA}" ;;
    *) fail "unknown label: ${label}" ;;
  esac

  cleanup_iteration
  OWNED_PID=""
  EXPECTED_EXECUTABLE="${derived}/Build/Products/Debug/MacVitals.app/Contents/MacOS/MacVitals"
  fail_on_foreign_macvitals || fail "foreign MacVitals blocks ${label} run ${iteration}"
  test -x "${EXPECTED_EXECUTABLE}" || fail "missing ${label} executable"

  rm -rf -- "${run_root}"
  mkdir -p "${run_root}" "${runtime_root}" "${isolated_home}/Library/Application Support" \
    "${isolated_home}/Library/Preferences" "${isolated_home}/tmp"
  rm -f -- "${ready}" "${stop}" "${complete}"

  CFFIXED_USER_HOME="${isolated_home}" \
  HOME="${isolated_home}" \
  TMPDIR="${isolated_home}/tmp" \
  "${EXPECTED_EXECUTABLE}" \
    -AppleLanguages '(en)' \
    -AppleLocale en_US \
    -notificationsEnabled NO \
    -showInDock NO \
    -samplingInterval 1 \
    > "${app_log}" 2>&1 &
  OWNED_PID=$!

  for _ in {1..80}; do
    exact_pid_is_owned "${OWNED_PID}" "${EXPECTED_EXECUTABLE}" && break
    sleep 0.25
  done
  exact_pid_is_owned "${OWNED_PID}" "${EXPECTED_EXECUTABLE}" \
    || fail "externally launched ${label} MacVitals did not stay alive"
  fail_on_foreign_macvitals || fail "foreign MacVitals appeared after ${label} launch"

  ps eww -p "${OWNED_PID}" -o command= > "${env_log}" 2>/dev/null || true
  if grep -Eq 'XCTestConfigurationFilePath=|XCInjectBundleInto=|[^[:space:]]+\.xctest([[:space:]]|$)' "${env_log}"; then
    fail "measured MacVitals contains in-process XCTest markers"
  fi
  grep -Fq "CFFIXED_USER_HOME=${isolated_home}" "${env_log}" \
    || fail "isolated application home was not applied"

  (
    cd "${root}"
    xcodebuild \
      -project MacVitals.xcodeproj \
      -scheme MacVitalsRealRuntimeWakeupAB \
      -configuration Debug \
      -destination 'platform=macOS' \
      -derivedDataPath "${derived}" \
      ARCHS=arm64 \
      ONLY_ACTIVE_ARCH=YES \
      CODE_SIGNING_ALLOWED=NO \
      test-without-building \
      '-only-testing:MacVitalsUITests/ProcessWakeupRealRuntimeABUITests/testExposeCPUDetailForExternalMeasurement'
  ) > "${test_log}" 2>&1 &
  TEST_PID=$!

  for _ in {1..180}; do
    [[ -f "${ready}" ]] && break
    if ! kill -0 "${TEST_PID}" 2>/dev/null; then
      break
    fi
    exact_pid_is_owned "${OWNED_PID}" "${EXPECTED_EXECUTABLE}" \
      || fail "${label} MacVitals exited before UI ready marker"
    sleep 0.25
  done
  if [[ ! -f "${ready}" ]]; then
    tail -n 300 "${test_log}" >&2 || true
    fail "${label} run ${iteration} did not expose CPU detail"
  fi
  grep -Fxq 'cpu-detail-active' "${ready}" || fail "invalid UI ready marker"
  exact_pid_is_owned "${OWNED_PID}" "${EXPECTED_EXECUTABLE}" \
    || fail "${label} process identity changed before measurement"
  fail_on_foreign_macvitals || fail "foreign MacVitals appeared before measurement"

  PROCESS_ID="${OWNED_PID}" \
  EXPECTED_EXECUTABLE_PATH="${EXPECTED_EXECUTABLE}" \
  OUTPUT_ROOT="${runtime_root}" \
    bash "${VALIDATION_ROOT}/scripts/collect_runtime_metrics.sh" 60 2 \
    > "${resource_log}" 2>&1 &
  RESOURCE_PID=$!

  set +e
  "${PROBE}" "${OWNED_PID}" 60 > "${probe_json}"
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
  exact_pid_is_owned "${OWNED_PID}" "${EXPECTED_EXECUTABLE}" \
    || fail "${label} process identity changed after measurement"

  printf '%s\n' 'external-measurement-complete' > "${stop}"

  for _ in {1..160}; do
    if ! kill -0 "${TEST_PID}" 2>/dev/null; then
      break
    fi
    sleep 0.25
  done
  if kill -0 "${TEST_PID}" 2>/dev/null; then
    fail "${label} UI driver did not finish after stop marker"
  fi
  set +e
  wait "${TEST_PID}"
  test_status=$?
  set -e
  TEST_PID=""
  if [[ ${test_status} -ne 0 ]]; then
    tail -n 300 "${test_log}" >&2 || true
    fail "${label} UI driver failed in run ${iteration}"
  fi
  grep -Eq '\*\* TEST( EXECUTE)? SUCCEEDED \*\*' "${test_log}" \
    || fail "${label} Xcode success marker missing"
  [[ -f "${complete}" ]] || fail "${label} completion marker missing"
  grep -Fxq 'cpu-detail-complete' "${complete}" || fail "invalid completion marker"

  for _ in {1..60}; do
    exact_pid_is_owned "${OWNED_PID}" "${EXPECTED_EXECUTABLE}" || break
    sleep 0.1
  done
  if exact_pid_is_owned "${OWNED_PID}" "${EXPECTED_EXECUTABLE}"; then
    fail "${label} MacVitals remained alive after graceful UI termination"
  fi
  OWNED_PID=""
  EXPECTED_EXECUTABLE=""
  fail_on_foreign_macvitals || fail "MacVitals remained after ${label} run ${iteration}"

  summaries="$(find "${runtime_root}" -mindepth 2 -maxdepth 2 -type f -name summary.json -print)"
  summary_count="$(printf '%s\n' "${summaries}" | awk 'NF { count += 1 } END { print count + 0 }')"
  [[ "${summary_count}" == "1" ]] || fail "${label} run ${iteration} expected one runtime summary"
  summary_path="$(printf '%s\n' "${summaries}" | awk 'NF { print; exit }')"
  python3 "${VALIDATION_ROOT}/scripts/report_runtime_resources.py" \
    "${summary_path}" \
    --scenario "real-runtime-${label}-run-${iteration}" \
    --source-sha "${sha}" \
    --output "${run_root}/resource-summary.json" \
    > "${run_root}/resource-summary.txt"

  python3 - "${probe_json}" "${run_root}/resource-summary.json" "${sha}" <<'PY'
import json
import math
import sys
from pathlib import Path
probe = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
resource = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
expected_sha = sys.argv[3]
if probe.get("schemaVersion") != 1 or float(probe.get("durationSeconds", 0)) < 59:
    raise SystemExit("wakeup observation is incomplete")
for key in ("packageIdleWakeupsPerSecond", "interruptWakeupsPerSecond"):
    value = probe.get(key)
    if not isinstance(value, (int, float)) or not math.isfinite(float(value)) or float(value) < 0:
        raise SystemExit(f"invalid wakeup metric: {key}")
if resource.get("sourceSha") != expected_sha:
    raise SystemExit("resource source SHA mismatch")
measurement = resource.get("measurement") or {}
if int(measurement.get("sampleCount", 0)) < 30 or float(measurement.get("durationSeconds", 0)) < 55:
    raise SystemExit("resource observation is incomplete")
PY
}

build_comparison() {
  python3 - "${EVIDENCE_DIR}" "${BASELINE_SHA}" "${CANDIDATE_SHA}" <<'PY'
import json
import statistics
import sys
from pathlib import Path
root = Path(sys.argv[1])
baseline_sha = sys.argv[2]
candidate_sha = sys.argv[3]

def load(label, iteration):
    run = root / label / f"run-{iteration}"
    wake = json.loads((run / "proc-rusage-wakeups.json").read_text(encoding="utf-8"))
    resource = json.loads((run / "resource-summary.json").read_text(encoding="utf-8"))
    measurement = resource.get("measurement") or {}
    return {
        "iteration": iteration,
        "interruptWakeupsPerSecond": float(wake["interruptWakeupsPerSecond"]),
        "packageIdleWakeupsPerSecond": float(wake["packageIdleWakeupsPerSecond"]),
        "cpuMean": float((measurement.get("cpuPercent") or {}).get("mean", 0)),
        "rssGrowthMiB": float((measurement.get("residentMemoryMiB") or {}).get("growth", 0)),
        "threadsMax": float((measurement.get("threads") or {}).get("max", 0)),
        "sampleCount": int(measurement.get("sampleCount", 0)),
        "durationSeconds": float(measurement.get("durationSeconds", 0)),
    }

baseline = [load("baseline", i) for i in (1, 2, 3)]
candidate = [load("candidate", i) for i in (1, 2, 3)]

def median(rows, key):
    return statistics.median(row[key] for row in rows)

paired = []
for left, right in zip(baseline, candidate):
    paired.append({
        "iteration": left["iteration"],
        "candidateMinusBaselineInterruptWakeupsPerSecond":
            right["interruptWakeupsPerSecond"] - left["interruptWakeupsPerSecond"],
        "candidateMinusBaselineCpuMean": right["cpuMean"] - left["cpuMean"],
    })

baseline_wakeup = median(baseline, "interruptWakeupsPerSecond")
candidate_wakeup = median(candidate, "interruptWakeupsPerSecond")
baseline_cpu = median(baseline, "cpuMean")
candidate_cpu = median(candidate, "cpuMean")
wakeup_lower_pairs = sum(
    1 for left, right in zip(baseline, candidate)
    if right["interruptWakeupsPerSecond"] < left["interruptWakeupsPerSecond"])
cpu_lower_pairs = sum(
    1 for left, right in zip(baseline, candidate)
    if right["cpuMean"] < left["cpuMean"])

result = {
    "schemaVersion": 1,
    "result": "collected-pending-independent-review",
    "method": "ordinary-MacVitals-process-controlled-by-external-XCUITest",
    "baselineSha": baseline_sha,
    "candidateSha": candidate_sha,
    "sameRunner": True,
    "uiDriverOutsideMeasuredProcess": True,
    "baseline": {
        "runs": baseline,
        "medianInterruptWakeupsPerSecond": baseline_wakeup,
        "medianCpuMean": baseline_cpu,
    },
    "candidate": {
        "runs": candidate,
        "medianInterruptWakeupsPerSecond": candidate_wakeup,
        "medianCpuMean": candidate_cpu,
    },
    "pairedDifferences": paired,
    "classification": {
        "candidateWakeupsLowerMedian": candidate_wakeup < baseline_wakeup,
        "candidateWakeupsLowerInAtLeastTwoOfThreePairs": wakeup_lower_pairs >= 2,
        "candidateCpuLowerMedian": candidate_cpu < baseline_cpu,
        "candidateCpuLowerInAtLeastTwoOfThreePairs": cpu_lower_pairs >= 2,
    },
}
(root / "real-runtime-comparison.json").write_text(
    json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(result, indent=2, sort_keys=True))
PY
}

[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] \
  || fail "native Apple Silicon macOS is required"
[[ -x "${PROBE}" ]] || fail "wakeup probe is missing"
[[ -f "${UI_SOURCE}" ]] || fail "UI driver source is missing"
[[ "$(git -C "${VALIDATION_ROOT}" rev-parse HEAD)" == "${VALIDATION_SHA}" ]] \
  || fail "checkout does not match exact validation SHA"

rm -rf -- "${WORK_ROOT}" "${EVIDENCE_DIR}"
mkdir -p "${WORK_ROOT}" "${EVIDENCE_DIR}/baseline" "${EVIDENCE_DIR}/candidate"
fail_on_foreign_macvitals || fail "pre-existing MacVitals blocks real-runtime A/B"

prepare_revision baseline "${BASELINE_SHA}"
prepare_revision candidate "${CANDIDATE_SHA}"

run_iteration baseline baseline 1
run_iteration candidate candidate 1
run_iteration candidate candidate 2
run_iteration baseline baseline 2
run_iteration baseline baseline 3
run_iteration candidate candidate 3

build_comparison
printf '%s\n' 'real-runtime-wakeup-ab=collected'
