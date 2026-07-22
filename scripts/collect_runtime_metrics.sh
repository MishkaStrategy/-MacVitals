#!/usr/bin/env bash
set -euo pipefail

DURATION_SECONDS="${1:-${DURATION_SECONDS:-300}}"
INTERVAL_SECONDS="${2:-${INTERVAL_SECONDS:-2}}"
PROCESS_NAME="${PROCESS_NAME:-MacVitals}"
PROCESS_ID="${PROCESS_ID:-}"
OUTPUT_ROOT="${OUTPUT_ROOT:-performance-results}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"
CSV_PATH="${OUTPUT_DIR}/samples.csv"
SUMMARY_PATH="${OUTPUT_DIR}/summary.json"

is_positive_number() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk -v value="$1" 'BEGIN { exit !(value > 0) }'
}

is_positive_number "${DURATION_SECONDS}" || {
  echo "Duration must be a positive number of seconds: ${DURATION_SECONDS}" >&2
  exit 2
}
is_positive_number "${INTERVAL_SECONDS}" || {
  echo "Interval must be a positive number of seconds: ${INTERVAL_SECONDS}" >&2
  exit 2
}

for command in pgrep ps date sleep awk python3 sw_vers uname sysctl; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required command is unavailable: ${command}" >&2
    exit 127
  }
done

if [[ -n "${PROCESS_ID}" ]]; then
  [[ "${PROCESS_ID}" =~ ^[0-9]+$ ]] || {
    echo "PROCESS_ID must be numeric: ${PROCESS_ID}" >&2
    exit 2
  }
  pid="${PROCESS_ID}"
else
  pid="$(pgrep -x "${PROCESS_NAME}" | head -n 1 || true)"
fi

[[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1 || {
  echo "${PROCESS_NAME} is not running. Launch the packaged app before collecting metrics." >&2
  exit 1
}

mkdir -p "${OUTPUT_DIR}"
echo "timestamp_utc,elapsed_seconds,cpu_percent,rss_kib,vsz_kib,threads" > "${CSV_PATH}"

thread_field_available=0
if ps -p "${pid}" -o thcount= >/dev/null 2>&1; then
  thread_field_available=1
fi

start_epoch="$(date +%s)"
end_epoch="$(awk -v start="${start_epoch}" -v duration="${DURATION_SECONDS}" 'BEGIN { printf "%.0f", start + duration }')"

while kill -0 "${pid}" >/dev/null 2>&1; do
  now_epoch="$(date +%s)"
  if (( now_epoch >= end_epoch )); then
    break
  fi

  cpu="$(ps -p "${pid}" -o %cpu= | awk '{$1=$1; print}')"
  rss="$(ps -p "${pid}" -o rss= | awk '{$1=$1; print}')"
  vsz="$(ps -p "${pid}" -o vsz= | awk '{$1=$1; print}')"
  threads=""
  if [[ "${thread_field_available}" -eq 1 ]]; then
    threads="$(ps -p "${pid}" -o thcount= | awk '{$1=$1; print}')"
  fi

  if [[ -n "${cpu}" && -n "${rss}" && -n "${vsz}" ]]; then
    elapsed="$((now_epoch - start_epoch))"
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "${timestamp},${elapsed},${cpu},${rss},${vsz},${threads}" >> "${CSV_PATH}"
  fi

  sleep "${INTERVAL_SECONDS}"
done

finished_epoch="$(date +%s)"
process_alive_at_end=false
if kill -0 "${pid}" >/dev/null 2>&1; then
  process_alive_at_end=true
fi

PROCESS_NAME="${PROCESS_NAME}" \
PROCESS_ID="${pid}" \
DURATION_SECONDS="${DURATION_SECONDS}" \
INTERVAL_SECONDS="${INTERVAL_SECONDS}" \
START_EPOCH="${start_epoch}" \
FINISHED_EPOCH="${finished_epoch}" \
PROCESS_ALIVE_AT_END="${process_alive_at_end}" \
CSV_PATH="${CSV_PATH}" \
SUMMARY_PATH="${SUMMARY_PATH}" \
python3 - <<'PY'
import csv
import json
import math
import os
import platform
import statistics
import subprocess
from pathlib import Path


def command(*args: str) -> str:
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def percentile(values: list[float], probability: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, math.ceil(probability * len(ordered)) - 1))
    return ordered[index]


def finite_nonnegative(value: str, field: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed) or parsed < 0:
        raise SystemExit(f"Invalid {field} sample: {value!r}")
    return parsed


csv_path = Path(os.environ["CSV_PATH"])
rows = list(csv.DictReader(csv_path.open(encoding="utf-8")))
if not rows:
    raise SystemExit("No process samples were collected")

elapsed = [finite_nonnegative(row["elapsed_seconds"], "elapsed") for row in rows]
cpu = [finite_nonnegative(row["cpu_percent"], "CPU") for row in rows]
rss = [finite_nonnegative(row["rss_kib"], "RSS") for row in rows]
vsz = [finite_nonnegative(row["vsz_kib"], "VSZ") for row in rows]
threads = [
    finite_nonnegative(row["threads"], "thread count")
    for row in rows
    if row["threads"].strip()
]
intervals = [later - earlier for earlier, later in zip(elapsed, elapsed[1:])]
if any(value < 0 for value in intervals):
    raise SystemExit("Elapsed sample times are not monotonic")

observed_duration = max(
    0,
    int(os.environ["FINISHED_EPOCH"]) - int(os.environ["START_EPOCH"]),
)
summary = {
    "schemaVersion": 2,
    "process": {
        "name": os.environ["PROCESS_NAME"],
        "pidAtStart": int(os.environ["PROCESS_ID"]),
        "aliveAtEnd": os.environ["PROCESS_ALIVE_AT_END"] == "true",
    },
    "requested": {
        "durationSeconds": float(os.environ["DURATION_SECONDS"]),
        "intervalSeconds": float(os.environ["INTERVAL_SECONDS"]),
    },
    "observed": {
        "durationSeconds": observed_duration,
        "firstSampleElapsedSeconds": elapsed[0],
        "lastSampleElapsedSeconds": elapsed[-1],
        "sampleCount": len(rows),
        "sampleIntervalSeconds": {
            "mean": statistics.fmean(intervals) if intervals else None,
            "p95": percentile(intervals, 0.95),
            "max": max(intervals) if intervals else None,
        },
    },
    "environment": {
        "architecture": platform.machine(),
        "macOSVersion": command("sw_vers", "-productVersion"),
        "macOSBuild": command("sw_vers", "-buildVersion"),
        "hardwareModel": command("sysctl", "-n", "hw.model"),
        "logicalCPUCount": command("sysctl", "-n", "hw.logicalcpu"),
        "physicalMemoryBytes": command("sysctl", "-n", "hw.memsize"),
    },
    "metrics": {
        "cpuPercent": {
            "mean": statistics.fmean(cpu),
            "p95": percentile(cpu, 0.95),
            "max": max(cpu),
        },
        "residentMemoryKiB": {
            "first": rss[0],
            "last": rss[-1],
            "growth": rss[-1] - rss[0],
            "range": max(rss) - min(rss),
            "mean": statistics.fmean(rss),
            "p95": percentile(rss, 0.95),
            "max": max(rss),
        },
        "virtualMemoryKiB": {
            "first": vsz[0],
            "last": vsz[-1],
            "growth": vsz[-1] - vsz[0],
            "mean": statistics.fmean(vsz),
            "p95": percentile(vsz, 0.95),
            "max": max(vsz),
        },
        "threads": {
            "mean": statistics.fmean(threads) if threads else None,
            "p95": percentile(threads, 0.95),
            "max": max(threads) if threads else None,
        },
    },
    "limitations": [
        "This is process sampling from ps, not an Instruments energy or wakeup trace.",
        "Values are evidence for the recorded machine and workload only.",
        "CI thresholds are broad regression guardrails, not product performance claims.",
        "No administrator privileges, network access, serial numbers, or user documents are used.",
    ],
}
Path(os.environ["SUMMARY_PATH"]).write_text(
    json.dumps(summary, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

echo "Runtime samples: ${CSV_PATH}"
echo "Runtime summary: ${SUMMARY_PATH}"