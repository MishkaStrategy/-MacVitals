#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_HELPER="${ROOT_DIR}/scripts/physical_runtime_lock.sh"
RUNNER="${ROOT_DIR}/scripts/run_ci_physical_validation_hardened.sh"
DOMAIN="com.mishkacher.MacVitals"
PREFS_BACKUP=""
PREFS_EXISTED=0
RUN_ROOT=""
RUN_APP=""
RUN_EXECUTABLE=""

fail() {
  printf 'safe-physical-validation: %s\n' "$*" >&2
  exit 1
}

[[ -f "${LOCK_HELPER}" && ! -L "${LOCK_HELPER}" ]] || fail "lock helper is missing or unsafe"
[[ -f "${RUNNER}" && ! -L "${RUNNER}" ]] || fail "hardened runner is missing or unsafe"
# shellcheck source=physical_runtime_lock.sh
source "${LOCK_HELPER}"

matching_run_pids() {
  local pid command_line
  [[ -n "${RUN_EXECUTABLE}" ]] || return 0
  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    command_line="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
    if [[ "${command_line}" == "${RUN_EXECUTABLE}" || "${command_line}" == "${RUN_EXECUTABLE} "* ]]; then
      printf '%s\n' "${pid}"
    fi
  done < <(pgrep -x MacVitals 2>/dev/null || true)
}

terminate_unique_run_processes() {
  local pid
  local pids=()
  while IFS= read -r pid; do
    [[ -n "${pid}" ]] && pids+=("${pid}")
  done < <(matching_run_pids)

  for pid in "${pids[@]}"; do
    kill -TERM "${pid}" 2>/dev/null || true
  done
  for _ in {1..40}; do
    local alive=0
    for pid in "${pids[@]}"; do
      if kill -0 "${pid}" 2>/dev/null; then
        alive=1
      fi
    done
    [[ ${alive} -eq 0 ]] && break
    sleep 0.25
  done
  for pid in "${pids[@]}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      kill -KILL "${pid}" 2>/dev/null || true
    fi
  done
}

restore_preferences() {
  local status=0
  if [[ -n "${PREFS_BACKUP}" ]]; then
    if [[ "${PREFS_EXISTED}" == "1" && -s "${PREFS_BACKUP}" ]]; then
      defaults import "${DOMAIN}" "${PREFS_BACKUP}" >/dev/null || status=$?
    else
      defaults delete "${DOMAIN}" >/dev/null 2>&1 || true
    fi
    rm -f -- "${PREFS_BACKUP}" || status=$?
    PREFS_BACKUP=""
  fi
  return "${status}"
}

cleanup() {
  local original_status="$1"
  local cleanup_status=0
  trap - EXIT INT TERM
  set +e

  terminate_unique_run_processes || cleanup_status=$?

  local foreign=0
  local pid command_line
  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    command_line="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
    if [[ -n "${command_line}" && "${command_line}" != "${RUN_EXECUTABLE}" && "${command_line}" != "${RUN_EXECUTABLE} "* ]]; then
      printf 'Foreign MacVitals process appeared during validation and was not terminated: pid=%s command=%s\n' \
        "${pid}" "${command_line}" >&2
      foreign=1
    fi
  done < <(pgrep -x MacVitals 2>/dev/null || true)
  [[ ${foreign} -eq 0 ]] || cleanup_status=1

  restore_preferences || cleanup_status=$?
  if [[ -n "${RUN_ROOT}" ]]; then
    rm -rf -- "${RUN_ROOT}" || cleanup_status=$?
    RUN_ROOT=""
  fi
  physical_runtime_lock_release || cleanup_status=$?

  if [[ "${original_status}" -ne 0 ]]; then
    exit "${original_status}"
  fi
  exit "${cleanup_status}"
}

handle_signal() {
  local status="$1"
  exit "${status}"
}

self_test() {
  bash -n "${LOCK_HELPER}" "${RUNNER}" "$0"
  bash "${LOCK_HELPER}" --self-test
  python3 - "$0" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
for forbidden in ("pkill", "killall MacVitals", "kill -TERM $(pgrep", "kill -KILL $(pgrep"):
    if forbidden in text:
        raise SystemExit(f"unsafe broad process operation found: {forbidden}")
for required in (
    "physical_runtime_lock_acquire",
    "Foreign MacVitals process appeared during validation and was not terminated",
    '"${command_line}" == "${RUN_EXECUTABLE}"',
    "defaults export",
    "defaults import",
    "physical_runtime_lock_release",
    "MACVITALS_RUN_LONG_STABILITY",
):
    if required not in text:
        raise SystemExit(f"safe physical wrapper contract is missing: {required}")
if text.index("restore_preferences") > text.index("physical_runtime_lock_release"):
    raise SystemExit("preferences must be restored before releasing the host lock")
print("Safe physical validation wrapper self-test passed")
PY
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit 0
fi

[[ $# -eq 3 ]] || fail "usage: $0 <version> <MacVitals.app> <expected-commit-sha>"
VERSION="$1"
APP_INPUT="$2"
EXPECTED_SHA="$3"
[[ "${EXPECTED_SHA}" =~ ^[0-9a-f]{40}$ ]] || fail "expected commit must be a full lowercase SHA-1"
[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || fail "native Apple Silicon macOS is required"
[[ -d "${APP_INPUT}" && ! -L "${APP_INPUT}" ]] || fail "input app is missing or unsafe"
[[ "$(git -C "${ROOT_DIR}" rev-parse HEAD)" == "${EXPECTED_SHA}" ]] || fail "checkout does not match expected SHA"

trap 'cleanup $?' EXIT
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM

physical_runtime_lock_acquire

if pgrep -x MacVitals >/dev/null 2>&1; then
  printf '%s\n' 'Existing MacVitals processes detected; validation fails closed and will not terminate them:' >&2
  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    ps -p "${pid}" -o pid=,command= >&2 || true
  done < <(pgrep -x MacVitals 2>/dev/null || true)
  fail "close existing MacVitals instances before physical validation"
fi

PREFS_BACKUP="$(mktemp "${TMPDIR:-/tmp}/macvitals-physical-preferences.XXXXXX")"
chmod 0600 "${PREFS_BACKUP}"
if defaults export "${DOMAIN}" "${PREFS_BACKUP}" >/dev/null 2>&1; then
  PREFS_EXISTED=1
else
  : > "${PREFS_BACKUP}"
  PREFS_EXISTED=0
fi

RUN_ID="${GITHUB_RUN_ID:-local}"
RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-1}"
[[ "${RUN_ID}" =~ ^[A-Za-z0-9._-]+$ && "${RUN_ATTEMPT}" =~ ^[A-Za-z0-9._-]+$ ]] || fail "unsafe run identity"
RUN_ROOT="${ROOT_DIR}/.physical-validation-run-${RUN_ID}-${RUN_ATTEMPT}-$$"
[[ ! -e "${RUN_ROOT}" && ! -L "${RUN_ROOT}" ]] || fail "unique run root already exists"
mkdir -m 700 "${RUN_ROOT}"
RUN_APP="${RUN_ROOT}/MacVitals.app"
ditto "${APP_INPUT}" "${RUN_APP}"
RUN_EXECUTABLE="${RUN_APP}/Contents/MacOS/MacVitals"
[[ -x "${RUN_EXECUTABLE}" && ! -L "${RUN_EXECUTABLE}" ]] || fail "unique candidate executable is missing or unsafe"
find "${RUN_APP}" -type l -print -quit | grep -q . && fail "unique candidate app contains symbolic links"

export MACVITALS_RUN_LONG_STABILITY="${MACVITALS_RUN_LONG_STABILITY:-0}"
case "${MACVITALS_RUN_LONG_STABILITY}" in
  0|1) ;;
  *) fail "MACVITALS_RUN_LONG_STABILITY must be 0 or 1" ;;
esac

bash "${RUNNER}" "${VERSION}" "${RUN_APP}" "${EXPECTED_SHA}"
