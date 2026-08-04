#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-${APP_PATH:-${ROOT_DIR}/build/MacVitals.xcarchive/Products/Applications/MacVitals.app}}"
EXECUTABLE_PATH="${APP_PATH}/Contents/MacOS/MacVitals"
WARMUP_SECONDS="${CI_RUNTIME_WARMUP_SECONDS:-5}"
DURATION_SECONDS="${CI_RUNTIME_DURATION_SECONDS:-45}"
INTERVAL_SECONDS="${CI_RUNTIME_INTERVAL_SECONDS:-2}"
OUTPUT_ROOT="${CI_RUNTIME_OUTPUT_ROOT:-${ROOT_DIR}/runtime-smoke-results}"
SCENARIO="${CI_RUNTIME_SCENARIO:-packaged-runtime-smoke}"
SOURCE_SHA="${GITHUB_SHA:-unknown}"
app_pid=""

cleanup() {
  if [[ -n "${app_pid}" ]] && kill -0 "${app_pid}" >/dev/null 2>&1; then
    kill -TERM "${app_pid}" >/dev/null 2>&1 || true
    for _ in {1..20}; do
      kill -0 "${app_pid}" >/dev/null 2>&1 || break
      sleep 0.25
    done
    if kill -0 "${app_pid}" >/dev/null 2>&1; then
      kill -KILL "${app_pid}" >/dev/null 2>&1 || true
    fi
    wait "${app_pid}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

for command in date find head mkdir tee tr wc python3; do
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
[[ -d "${APP_PATH}" ]] || {
  echo "Packaged application is missing" >&2
  exit 1
}
[[ -x "${EXECUTABLE_PATH}" ]] || {
  echo "Packaged executable is missing or not executable" >&2
  exit 1
}

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
  if kill -0 "${app_pid}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done
kill -0 "${app_pid}" >/dev/null 2>&1 || {
  echo "MacVitals exited during startup" >&2
  cat "${APP_LOG}" >&2 || true
  exit 1
}

sleep "${WARMUP_SECONDS}"
kill -0 "${app_pid}" >/dev/null 2>&1 || {
  echo "MacVitals exited during the runtime warmup" >&2
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
