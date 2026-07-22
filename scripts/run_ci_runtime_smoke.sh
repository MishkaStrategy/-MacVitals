#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-${APP_PATH:-${ROOT_DIR}/build/MacVitals.xcarchive/Products/Applications/MacVitals.app}}"
EXECUTABLE_PATH="${APP_PATH}/Contents/MacOS/MacVitals"
DURATION_SECONDS="${CI_RUNTIME_DURATION_SECONDS:-45}"
INTERVAL_SECONDS="${CI_RUNTIME_INTERVAL_SECONDS:-2}"
OUTPUT_ROOT="${CI_RUNTIME_OUTPUT_ROOT:-${ROOT_DIR}/runtime-smoke-results}"
APP_LOG="${OUTPUT_ROOT}/MacVitals.log"
VALIDATION_LOG="${OUTPUT_ROOT}/validation.log"
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

[[ -d "${APP_PATH}" ]] || {
  echo "Packaged application is missing: ${APP_PATH}" >&2
  exit 1
}
[[ -x "${EXECUTABLE_PATH}" ]] || {
  echo "Packaged executable is missing or not executable: ${EXECUTABLE_PATH}" >&2
  exit 1
}

rm -rf "${OUTPUT_ROOT}"
mkdir -p "${OUTPUT_ROOT}"

"${EXECUTABLE_PATH}" \
  -AppleLanguages '(en)' \
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

PROCESS_NAME="MacVitals" \
PROCESS_ID="${app_pid}" \
OUTPUT_ROOT="${OUTPUT_ROOT}/samples" \
bash "${ROOT_DIR}/scripts/collect_runtime_metrics.sh" \
  "${DURATION_SECONDS}" \
  "${INTERVAL_SECONDS}"

mapfile -t summaries < <(find "${OUTPUT_ROOT}/samples" -name summary.json -type f -print)
[[ "${#summaries[@]}" -eq 1 ]] || {
  echo "Expected exactly one runtime summary, found ${#summaries[@]}" >&2
  exit 1
}
summary_path="${summaries[0]}"

python3 "${ROOT_DIR}/scripts/validate_runtime_metrics.py" \
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

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  SUMMARY_PATH="${summary_path}" python3 - <<'PY' >> "${GITHUB_STEP_SUMMARY}"
import json
import os
from pathlib import Path

summary = json.loads(Path(os.environ["SUMMARY_PATH"]).read_text(encoding="utf-8"))
metrics = summary["metrics"]
observed = summary["observed"]
print("## Runtime smoke guardrail")
print()
print("Hosted-runner regression evidence only; this is not a physical-device benchmark.")
print()
print("| Metric | Observed |")
print("|---|---:|")
print(f"| Samples | {observed['sampleCount']} |")
print(f"| Duration | {observed['durationSeconds']:.1f} s |")
print(f"| Mean process CPU | {metrics['cpuPercent']['mean']:.2f}% |")
print(f"| p95 process CPU | {metrics['cpuPercent']['p95']:.2f}% |")
print(f"| Peak RSS | {metrics['residentMemoryKiB']['max'] / 1024:.2f} MiB |")
print(f"| RSS growth | {metrics['residentMemoryKiB']['growth'] / 1024:.2f} MiB |")
threads = metrics["threads"]["max"]
print(f"| Peak threads | {threads:.0f} |" if threads is not None else "| Peak threads | unavailable |")
PY
fi

echo "Runtime smoke artifacts: ${OUTPUT_ROOT}"