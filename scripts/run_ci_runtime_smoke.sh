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

APP_PATH="${1:-${APP_PATH:-${ROOT_DIR}/build/MacVitals.xcarchive/Products/Applications/MacVitals.app}}"
EXECUTABLE_PATH="${APP_PATH}/Contents/MacOS/MacVitals"
WARMUP_SECONDS="${CI_RUNTIME_WARMUP_SECONDS:-5}"
DURATION_SECONDS="${CI_RUNTIME_DURATION_SECONDS:-45}"
INTERVAL_SECONDS="${CI_RUNTIME_INTERVAL_SECONDS:-2}"
OUTPUT_ROOT="${CI_RUNTIME_OUTPUT_ROOT:-${ROOT_DIR}/runtime-smoke-results}"
SCENARIO="${CI_RUNTIME_SCENARIO:-packaged-runtime-smoke}"
SOURCE_SHA="${GITHUB_SHA:-unknown}"
app_pid=""

owned_process_is_running() {
  local command_line
  [[ -n "${app_pid}" && "${app_pid}" =~ ^[0-9]+$ ]] || return 1
  kill -0 "${app_pid}" >/dev/null 2>&1 || return 1
  command_line="$(ps -p "${app_pid}" -o command= 2>/dev/null || true)"
  [[ "${command_line}" == "${EXECUTABLE_PATH}" || "${command_line}" == "${EXECUTABLE_PATH} "* ]]
}

foreign_macvitals_count() {
  local pid command_line count=0
  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    command_line="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
    if [[ "${pid}" != "${app_pid}" || ( "${command_line}" != "${EXECUTABLE_PATH}" && "${command_line}" != "${EXECUTABLE_PATH} "* ) ]]; then
      echo "Foreign MacVitals process was not terminated: pid=${pid} command=${command_line}" >&2
      count=$((count + 1))
    fi
  done < <(pgrep -x MacVitals 2>/dev/null || true)
  printf '%s\n' "${count}"
}

cleanup() {
  local original_status=$?
  local cleanup_status=0 foreign_count
  trap - EXIT INT TERM
  set +e

  if owned_process_is_running; then
    kill -TERM "${app_pid}" >/dev/null 2>&1 || true
    for _ in {1..20}; do
      owned_process_is_running || break
      sleep 0.25
    done
    if owned_process_is_running; then
      kill -KILL "${app_pid}" >/dev/null 2>&1 || true
    fi
  fi
  if [[ -n "${app_pid}" ]]; then
    wait "${app_pid}" 2>/dev/null || true
  fi

  foreign_count="$(foreign_macvitals_count)"
  [[ "${foreign_count}" == "0" ]] || cleanup_status=1
  app_pid=""

  physical_runtime_lock_release || cleanup_status=$?

  if [[ ${original_status} -ne 0 ]]; then
    exit "${original_status}"
  fi
  exit "${cleanup_status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for command in awk bash cat chmod date find grep head mkdir mv pgrep ps python3 rm rmdir sleep stat tee tr wc; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required runtime-smoke command is unavailable: ${command}" >&2
    exit 127
  }
done

[[ "${WARMUP_SECONDS}" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
  echo "Warmup duration must be a non-negative number: ${WARMUP_SECONDS}" >&2
  exit 2
}
[[ "${DURATION_SECONDS}" =~ ^[0-9]+$ ]] && (( 10#${DURATION_SECONDS} > 0 )) || {
  echo "Runtime duration must be a positive whole number of seconds: ${DURATION_SECONDS}" >&2
  exit 2
}
[[ "${INTERVAL_SECONDS}" =~ ^[0-9]+([.][0-9]+)?$ ]] \
  && awk -v value="${INTERVAL_SECONDS}" 'BEGIN { exit !(value > 0) }' || {
  echo "Runtime interval must be a positive number of seconds: ${INTERVAL_SECONDS}" >&2
  exit 2
}
[[ "${SCENARIO}" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "Runtime scenario contains unsafe characters: ${SCENARIO}" >&2
  exit 2
}
if [[ ! "${SOURCE_SHA}" =~ ^[0-9a-f]{40}$ ]]; then
  SOURCE_SHA="unknown"
fi
[[ -d "${APP_PATH}" && ! -L "${APP_PATH}" ]] || {
  echo "Packaged application is missing or unsafe" >&2
  exit 1
}
[[ -x "${EXECUTABLE_PATH}" && ! -L "${EXECUTABLE_PATH}" ]] || {
  echo "Packaged executable is missing or unsafe" >&2
  exit 1
}
find "${APP_PATH}" -type l -print -quit | grep -q . && {
  echo "Packaged application contains symbolic links" >&2
  exit 1
}

physical_runtime_lock_acquire

existing="$(pgrep -x MacVitals 2>/dev/null || true)"
if [[ -n "${existing}" ]]; then
  echo "Existing MacVitals processes detected; runtime smoke fails closed and will not terminate them:" >&2
  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    ps -p "${pid}" -o pid=,command= >&2 || true
  done <<< "${existing}"
  exit 1
fi

BASE_OUTPUT_ROOT="$(python3 "${ROOT_DIR}/scripts/validate_output_path.py" --root "${ROOT_DIR}" --path "${OUTPUT_ROOT}")"
RUN_ID="run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
OUTPUT_ROOT="${BASE_OUTPUT_ROOT}/${RUN_ID}"
BASE_OUTPUT_ROOT="${BASE_OUTPUT_ROOT}" python3 - <<'PY'
import os
import re
from pathlib import Path

base = Path(os.environ["BASE_OUTPUT_ROOT"])
run_name = re.compile(r"run-[0-9]{8}T[0-9]{6}Z-[0-9]+\Z")
if base.exists():
    if not base.is_dir():
        raise SystemExit("Runtime output base is not a directory")
    unexpected = [
        entry.name
        for entry in base.iterdir()
        if not (entry.is_dir() and not entry.is_symlink() and run_name.fullmatch(entry.name))
    ]
    if unexpected:
        raise SystemExit(
            "Refusing runtime output base with unexpected entries: "
            + ", ".join(sorted(unexpected))
        )
PY
mkdir -p -- "${BASE_OUTPUT_ROOT}"
mkdir -- "${OUTPUT_ROOT}"
APP_LOG="${OUTPUT_ROOT}/MacVitals.log"
VALIDATION_LOG="${OUTPUT_ROOT}/validation.log"

"${EXECUTABLE_PATH}" \
  -AppleLanguages '(en)' \
  -AppleLocale en_US \
  -notificationsEnabled NO \
  -showInDock NO \
  -samplingInterval 2 \
  >"${APP_LOG}" 2>&1 &
app_pid="$!"

for _ in {1..40}; do
  owned_process_is_running && break
  sleep 0.25
done
owned_process_is_running || {
  echo "MacVitals exited during startup or process identity changed" >&2
  cat "${APP_LOG}" >&2 || true
  exit 1
}

sleep "${WARMUP_SECONDS}"
owned_process_is_running || {
  echo "MacVitals exited during the runtime warmup or process identity changed" >&2
  cat "${APP_LOG}" >&2 || true
  exit 1
}

PROCESS_NAME="MacVitals" \
PROCESS_ID="${app_pid}" \
EXPECTED_EXECUTABLE_PATH="${EXECUTABLE_PATH}" \
OUTPUT_ROOT="${OUTPUT_ROOT}/samples" \
bash "${ROOT_DIR}/scripts/collect_runtime_metrics.sh" \
  "${DURATION_SECONDS}" \
  "${INTERVAL_SECONDS}"

summary_count="$(find "${OUTPUT_ROOT}/samples" -name summary.json -type f -print | wc -l | tr -d '[:space:]')"
[[ "${summary_count}" == "1" ]] || {
  echo "Expected exactly one runtime summary, found ${summary_count}" >&2
  exit 1
}
summary_path="$(find "${OUTPUT_ROOT}/samples" -name summary.json -type f -print | head -n 1)"

python3 "${ROOT_DIR}/scripts/validate_runtime_metrics_hardened.py" \
  "${summary_path}" \
  --minimum-samples "${CI_RUNTIME_MINIMUM_SAMPLES:-10}" \
  --minimum-observed-seconds "${CI_RUNTIME_MINIMUM_OBSERVED_SECONDS:-30}" \
  --maximum-mean-cpu-percent "${CI_RUNTIME_MAXIMUM_MEAN_CPU_PERCENT:-75}" \
  --maximum-p95-cpu-percent "${CI_RUNTIME_MAXIMUM_P95_CPU_PERCENT:-200}" \
  --maximum-rss-mib "${CI_RUNTIME_MAXIMUM_RSS_MIB:-512}" \
  --maximum-rss-growth-mib "${CI_RUNTIME_MAXIMUM_RSS_GROWTH_MIB:-128}" \
  --maximum-threads "${CI_RUNTIME_MAXIMUM_THREADS:-128}" \
  --maximum-interval-multiplier "${CI_RUNTIME_MAXIMUM_INTERVAL_MULTIPLIER:-6}" \
  | tee "${VALIDATION_LOG}"

python3 "${ROOT_DIR}/scripts/report_runtime_resources.py" \
  "${summary_path}" \
  --scenario "${SCENARIO}" \
  --source-sha "${SOURCE_SHA}" \
  --output "${OUTPUT_ROOT}/resource-summary.json"

EVIDENCE_ROOT="${OUTPUT_ROOT}" python3 - <<'PY'
import os
import re
from pathlib import Path

root = Path(os.environ["EVIDENCE_ROOT"])
home = str(Path.home())
home_pattern = re.compile(r"/(?:Users|home)/[^/\s]+")
violations: list[str] = []
for path in root.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    if (home and home in text) or home_pattern.search(text):
        violations.append(str(path.relative_to(root)))
if violations:
    raise SystemExit(
        "Runtime evidence contains a user home path: " + ", ".join(sorted(violations))
    )
print("Runtime evidence privacy validation passed")
PY

echo "Runtime smoke artifacts were generated."
