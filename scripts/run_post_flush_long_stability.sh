#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLLECTOR="${ROOT_DIR}/scripts/collect_runtime_metrics.sh"
REPORTER="${ROOT_DIR}/scripts/report_runtime_resources.py"
DURATION_SECONDS="${MACVITALS_STABILITY_DURATION_SECONDS:-21600}"
SAMPLE_INTERVAL_SECONDS="${MACVITALS_STABILITY_SAMPLE_INTERVAL_SECONDS:-30}"
POWER_POLL_SECONDS="${MACVITALS_STABILITY_POWER_POLL_SECONDS:-30}"
OWNED_PID=""
EXPECTED_EXECUTABLE=""
COLLECTOR_PID=""
POWER_LOST=0

fail() {
  printf 'post-flush-long-stability: %s\n' "$*" >&2
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

external_power_available() {
  pmset -g batt 2>/dev/null | head -n 1 | grep -Eq "AC Power|Adapter"
}

crash_report_paths() {
  local destination="$1"
  local root="${HOME}/Library/Logs/DiagnosticReports"
  : > "${destination}"
  [[ -d "${root}" && ! -L "${root}" ]] || return 0
  find "${root}" -maxdepth 1 -type f \
    \( -name 'MacVitals*.ips' -o -name 'MacVitals*.crash' \) \
    -print | LC_ALL=C sort > "${destination}"
}

cleanup() {
  local original_status="$?"
  trap - EXIT HUP INT TERM
  set +e
  if [[ -n "${COLLECTOR_PID}" ]] && kill -0 "${COLLECTOR_PID}" 2>/dev/null; then
    kill -TERM "${COLLECTOR_PID}" 2>/dev/null || true
    wait "${COLLECTOR_PID}" 2>/dev/null || true
  fi
  terminate_exact_pid "${OWNED_PID}" "${EXPECTED_EXECUTABLE}" || true
  exit "${original_status}"
}

self_test() {
  bash -n "$0"
  python3 - "$0" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text(encoding="utf-8")
required = (
    "exact_pid_is_owned",
    "terminate_exact_pid",
    "EXPECTED_EXECUTABLE_PATH",
    "collect_runtime_metrics.sh",
    "report_runtime_resources.py",
    "external_power_available",
    "POWER_LOST",
)
for marker in required:
    if marker not in text:
        raise SystemExit(f"long-stability contract marker missing: {marker}")
for forbidden in ("p" + "kill", "kill" + "all MacVitals"):
    if forbidden in text:
        raise SystemExit(f"broad process termination is forbidden: {forbidden}")
print("Post-flush long-stability harness self-test passed")
PY
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit 0
fi

[[ $# -eq 3 ]] || fail "usage: $0 <MacVitals.app> <expected-validation-sha> <output-directory>"
APP_INPUT="$1"
EXPECTED_SHA="$2"
OUTPUT_ROOT="$3"

[[ "${EXPECTED_SHA}" =~ ^[0-9a-f]{40}$ ]] || fail "expected SHA must be a full lowercase SHA-1"
[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || fail "native Apple Silicon macOS is required"
[[ "$(git -C "${ROOT_DIR}" rev-parse HEAD)" == "${EXPECTED_SHA}" ]] || fail "checkout does not match expected validation SHA"
[[ "${DURATION_SECONDS}" =~ ^[0-9]+$ && "${DURATION_SECONDS}" -ge 60 ]] || fail "stability duration must be at least 60 seconds"
[[ "${SAMPLE_INTERVAL_SECONDS}" =~ ^[0-9]+$ && "${SAMPLE_INTERVAL_SECONDS}" -ge 1 ]] || fail "sample interval is invalid"
[[ "${POWER_POLL_SECONDS}" =~ ^[0-9]+$ && "${POWER_POLL_SECONDS}" -ge 1 ]] || fail "power poll interval is invalid"
[[ -d "${APP_INPUT}" && ! -L "${APP_INPUT}" ]] || fail "input app is missing or unsafe"
APP="$(cd "$(dirname "${APP_INPUT}")" && pwd -P)/$(basename "${APP_INPUT}")"
EXPECTED_EXECUTABLE="${APP}/Contents/MacOS/MacVitals"
[[ -f "${EXPECTED_EXECUTABLE}" && ! -L "${EXPECTED_EXECUTABLE}" && -x "${EXPECTED_EXECUTABLE}" ]] || fail "MacVitals executable is missing or unsafe"
[[ -f "${COLLECTOR}" && ! -L "${COLLECTOR}" ]] || fail "canonical runtime collector is unavailable"
[[ -f "${REPORTER}" && ! -L "${REPORTER}" ]] || fail "canonical runtime reporter is unavailable"
mkdir -p "${OUTPUT_ROOT}"
[[ -d "${OUTPUT_ROOT}" && ! -L "${OUTPUT_ROOT}" ]] || fail "output directory is unsafe"

trap cleanup EXIT HUP INT TERM

if pgrep -x MacVitals >/dev/null 2>&1; then
  printf '%s\n' 'Existing MacVitals process detected; long stability fails closed and will not terminate it:' >&2
  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    ps -p "${pid}" -o pid=,command= >&2 || true
  done < <(pgrep -x MacVitals 2>/dev/null || true)
  fail "existing MacVitals instance prevents long stability validation"
fi

external_power_available || fail "six-hour stability requires external power"

CRASH_BEFORE="${OUTPUT_ROOT}/crash-before.txt"
CRASH_AFTER="${OUTPUT_ROOT}/crash-after.txt"
crash_report_paths "${CRASH_BEFORE}"

/usr/bin/open -na "${APP}" --args -notificationsEnabled NO -showInDock NO
for _ in {1..120}; do
  owned_count=0
  candidate=""
  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    command_line="$(command_for_pid "${pid}")"
    [[ -n "${command_line}" ]] || continue
    if [[ "${command_line}" == "${EXPECTED_EXECUTABLE}" || "${command_line}" == "${EXPECTED_EXECUTABLE} "* ]]; then
      candidate="${pid}"
      owned_count=$((owned_count + 1))
    else
      printf 'Foreign MacVitals process appeared and will not be terminated: pid=%s command=%s\n' "${pid}" "${command_line}" >&2
      fail "foreign MacVitals process appeared during launch"
    fi
  done < <(pgrep -x MacVitals 2>/dev/null || true)
  [[ ${owned_count} -le 1 ]] || fail "multiple validation-owned MacVitals processes appeared"
  if [[ ${owned_count} -eq 1 ]]; then
    OWNED_PID="${candidate}"
    break
  fi
  sleep 0.25
done
[[ -n "${OWNED_PID}" ]] || fail "validation-owned MacVitals process did not appear"
exact_pid_is_owned "${OWNED_PID}" "${EXPECTED_EXECUTABLE}" || fail "validation-owned MacVitals identity is invalid"

RESOURCE_ROOT="${OUTPUT_ROOT}/runtime"
mkdir -p "${RESOURCE_ROOT}"
PROCESS_ID="${OWNED_PID}" \
EXPECTED_EXECUTABLE_PATH="${EXPECTED_EXECUTABLE}" \
OUTPUT_ROOT="${RESOURCE_ROOT}" \
  bash "${COLLECTOR}" "${DURATION_SECONDS}" "${SAMPLE_INTERVAL_SECONDS}" \
  > "${OUTPUT_ROOT}/runtime-collector.log" 2>&1 &
COLLECTOR_PID=$!

while kill -0 "${COLLECTOR_PID}" 2>/dev/null; do
  sleep "${POWER_POLL_SECONDS}"
  if ! external_power_available; then
    POWER_LOST=1
    printf '%s\n' 'External power was lost during long stability; stopping validation-owned MacVitals.' >&2
    terminate_exact_pid "${OWNED_PID}" "${EXPECTED_EXECUTABLE}" || true
    break
  fi
  if ! exact_pid_is_owned "${OWNED_PID}" "${EXPECTED_EXECUTABLE}"; then
    printf '%s\n' 'Validation-owned MacVitals exited before the long stability window completed.' >&2
    break
  fi
done

set +e
wait "${COLLECTOR_PID}"
COLLECTOR_STATUS=$?
set -e
COLLECTOR_PID=""
cat "${OUTPUT_ROOT}/runtime-collector.log"

if [[ ${POWER_LOST} -eq 1 ]]; then
  printf 'powerLoss=true\n' > "${OUTPUT_ROOT}/POWER_LOST.txt"
  exit 75
fi
[[ ${COLLECTOR_STATUS} -eq 0 ]] || fail "canonical runtime collector failed with exit ${COLLECTOR_STATUS}"
exact_pid_is_owned "${OWNED_PID}" "${EXPECTED_EXECUTABLE}" || fail "MacVitals did not remain alive through the stability window"

summaries="$(find "${RESOURCE_ROOT}" -mindepth 2 -maxdepth 2 -type f -name summary.json -print)"
summary_count="$(printf '%s\n' "${summaries}" | awk 'NF { count += 1 } END { print count + 0 }')"
[[ "${summary_count}" == "1" ]] || fail "expected exactly one runtime summary"
summary_path="$(printf '%s\n' "${summaries}" | awk 'NF { print; exit }')"
PRODUCT_SHA="${PRODUCT_BASE_SHA:-${EXPECTED_SHA}}"
python3 "${REPORTER}" \
  "${summary_path}" \
  --scenario post-flush-six-hour-stability \
  --source-sha "${PRODUCT_SHA}" \
  --output "${OUTPUT_ROOT}/resource-summary.json" \
  | tee "${OUTPUT_ROOT}/resource-summary.txt"

crash_report_paths "${CRASH_AFTER}"
comm -13 "${CRASH_BEFORE}" "${CRASH_AFTER}" > "${OUTPUT_ROOT}/new-crash-reports.txt"
if [[ -s "${OUTPUT_ROOT}/new-crash-reports.txt" ]]; then
  fail "new MacVitals crash report appeared during long stability"
fi

python3 - \
  "${OUTPUT_ROOT}/resource-summary.json" \
  "${DURATION_SECONDS}" \
  "${PRODUCT_SHA}" \
  "${OUTPUT_ROOT}/long-stability-summary.json" <<'PY'
from pathlib import Path
import json
import math
import sys
resource_path = Path(sys.argv[1])
expected_duration = int(sys.argv[2])
product_sha = sys.argv[3]
target = Path(sys.argv[4])
resource = json.loads(resource_path.read_text(encoding="utf-8"))
if resource.get("sourceSha") != product_sha:
    raise SystemExit("long-stability source SHA mismatch")
if resource.get("scenario") != "post-flush-six-hour-stability":
    raise SystemExit("long-stability scenario mismatch")
process = resource.get("process") or {}
if process.get("name") != "MacVitals" or process.get("identityStable") is not True or process.get("aliveAtEnd") is not True:
    raise SystemExit("long-stability process identity was not stable/alive")
measurement = resource.get("measurement") or {}
duration = float(measurement.get("durationSeconds", 0))
minimum_duration = max(55, expected_duration - max(60, expected_duration * 0.01))
if duration < minimum_duration:
    raise SystemExit(f"long-stability duration is too short: {duration}")
expected_samples = int(expected_duration / 30) + 1 if expected_duration >= 21600 else 2
if int(measurement.get("sampleCount", 0)) < min(expected_samples, 700 if expected_duration >= 21600 else expected_samples):
    raise SystemExit("long-stability sample count is insufficient")
rss = measurement.get("residentMemoryMiB") or {}
threads = measurement.get("threads") or {}
for value in (rss.get("growth"), rss.get("peak"), threads.get("max")):
    if value is None or not math.isfinite(float(value)):
        raise SystemExit("long-stability resource evidence is incomplete")
result = {
    "schemaVersion": 1,
    "result": "passed",
    "productSha": product_sha,
    "requestedDurationSeconds": expected_duration,
    "measuredDurationSeconds": duration,
    "sampleCount": measurement.get("sampleCount"),
    "cpu": measurement.get("cpuPercent"),
    "residentMemoryMiB": rss,
    "threads": threads,
    "externalPowerMaintained": True,
    "newCrashReportCount": 0,
}
target.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

printf 'long-stability=passed\n' > "${OUTPUT_ROOT}/LONG_STABILITY_PASSED.txt"
terminate_exact_pid "${OWNED_PID}" "${EXPECTED_EXECUTABLE}" || fail "validation-owned MacVitals could not be terminated safely"
OWNED_PID=""
