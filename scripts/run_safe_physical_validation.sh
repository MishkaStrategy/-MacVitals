#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_HELPER="${ROOT_DIR}/scripts/physical_runtime_lock.sh"
RUNNER="${ROOT_DIR}/scripts/run_ci_physical_validation_hardened.sh"
DOMAIN="com.mishkacher.MacVitals"
PREFS_BACKUP=""
PREFS_VERIFY=""
PREFS_CAPTURED=0
PREFS_EXISTED=0
RUN_ROOT=""
RUN_APP=""
RUN_EXECUTABLE=""
CRASH_BEFORE=""
CRASH_AFTER=""
EVIDENCE_ROOT="${ROOT_DIR}/physical-validation-results"

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
  local pid alive
  local pids=()
  while IFS= read -r pid; do
    [[ -n "${pid}" ]] && pids+=("${pid}")
  done < <(matching_run_pids)

  for pid in "${pids[@]}"; do
    kill -TERM "${pid}" 2>/dev/null || true
  done
  for _ in {1..40}; do
    alive=0
    for pid in "${pids[@]}"; do
      kill -0 "${pid}" 2>/dev/null && alive=1
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

domain_appears_to_exist() {
  local plist="${HOME}/Library/Preferences/${DOMAIN}.plist"
  [[ -e "${plist}" || -L "${plist}" ]] && return 0
  defaults read "${DOMAIN}" >/dev/null 2>&1
}

capture_preferences() {
  PREFS_BACKUP="$(mktemp "${TMPDIR:-/tmp}/macvitals-physical-preferences.XXXXXX")"
  chmod 0600 "${PREFS_BACKUP}"
  if defaults export "${DOMAIN}" "${PREFS_BACKUP}" >/dev/null 2>&1; then
    PREFS_EXISTED=1
    [[ -s "${PREFS_BACKUP}" ]] || fail "preferences export produced an empty backup"
  else
    if domain_appears_to_exist; then
      fail "preferences domain appears to exist but could not be exported"
    fi
    : > "${PREFS_BACKUP}"
    PREFS_EXISTED=0
  fi
  PREFS_CAPTURED=1
}

verify_restored_preferences() {
  if [[ "${PREFS_EXISTED}" == "1" ]]; then
    PREFS_VERIFY="$(mktemp "${TMPDIR:-/tmp}/macvitals-physical-preferences-verify.XXXXXX")"
    chmod 0600 "${PREFS_VERIFY}"
    defaults export "${DOMAIN}" "${PREFS_VERIFY}" >/dev/null
    python3 - "${PREFS_BACKUP}" "${PREFS_VERIFY}" <<'PY'
import plistlib
import sys
from pathlib import Path

before = plistlib.loads(Path(sys.argv[1]).read_bytes())
after = plistlib.loads(Path(sys.argv[2]).read_bytes())
if before != after:
    raise SystemExit("restored preferences differ from the captured plist")
PY
    rm -f -- "${PREFS_VERIFY}"
    PREFS_VERIFY=""
  else
    if domain_appears_to_exist; then
      printf '%s\n' 'Preferences domain unexpectedly exists after absent-domain restoration' >&2
      return 1
    fi
  fi
}

restore_preferences() {
  local status=0
  [[ "${PREFS_CAPTURED}" == "1" ]] || {
    [[ -z "${PREFS_BACKUP}" ]] || rm -f -- "${PREFS_BACKUP}"
    PREFS_BACKUP=""
    return 0
  }

  if [[ "${PREFS_EXISTED}" == "1" && -s "${PREFS_BACKUP}" ]]; then
    defaults import "${DOMAIN}" "${PREFS_BACKUP}" >/dev/null || status=$?
  else
    defaults delete "${DOMAIN}" >/dev/null 2>&1 || true
  fi
  if [[ ${status} -eq 0 ]]; then
    verify_restored_preferences || status=$?
  fi
  if [[ ${status} -eq 0 ]]; then
    rm -f -- "${PREFS_BACKUP}"
    PREFS_BACKUP=""
    PREFS_CAPTURED=0
  fi
  return "${status}"
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

record_new_crash_reports() {
  local new_list path name bytes digest count=0
  [[ -n "${CRASH_BEFORE}" && -n "${CRASH_AFTER}" ]] || return 0
  mkdir -p "${EVIDENCE_ROOT}"
  new_list="$(mktemp "${TMPDIR:-/tmp}/macvitals-new-crash-reports.XXXXXX")"
  comm -13 "${CRASH_BEFORE}" "${CRASH_AFTER}" > "${new_list}"
  {
    printf 'schemaVersion=1\n'
    while IFS= read -r path; do
      [[ -n "${path}" ]] || continue
      if [[ ! -f "${path}" || -L "${path}" ]]; then
        printf 'unsafe-entry=%s\n' "$(basename "${path}")"
        count=$((count + 1))
        continue
      fi
      name="$(basename "${path}")"
      bytes="$(stat -f %z "${path}" 2>/dev/null || printf 'unknown')"
      digest="$(shasum -a 256 "${path}" | awk '{print $1}')"
      printf 'report=%s bytes=%s sha256=%s\n' "${name}" "${bytes}" "${digest}"
      count=$((count + 1))
    done < "${new_list}"
    printf 'newReportCount=%s\n' "${count}"
  } > "${EVIDENCE_ROOT}/crash-report-manifest.txt"
  rm -f -- "${new_list}"
  [[ ${count} -eq 0 ]]
}

foreign_macvitals_count() {
  local pid command_line count=0
  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    command_line="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
    if [[ -n "${command_line}" && "${command_line}" != "${RUN_EXECUTABLE}" && "${command_line}" != "${RUN_EXECUTABLE} "* ]]; then
      printf 'Foreign MacVitals process appeared and was not terminated: pid=%s command=%s\n' \
        "${pid}" "${command_line}" >&2
      count=$((count + 1))
    fi
  done < <(pgrep -x MacVitals 2>/dev/null || true)
  printf '%s\n' "${count}"
}

cleanup() {
  local original_status="$1"
  local cleanup_status=0 foreign_count restore_status=0
  trap - EXIT INT TERM
  set +e

  terminate_unique_run_processes || cleanup_status=$?
  foreign_count="$(foreign_macvitals_count)"
  [[ "${foreign_count}" == "0" ]] || cleanup_status=1

  restore_preferences || restore_status=$?
  if [[ ${restore_status} -ne 0 ]]; then
    physical_runtime_lock_mark_recovery_required \
      "domain=${DOMAIN} backup=${PREFS_BACKUP} restore_status=${restore_status}" || true
    printf 'Preference recovery failed; backup preserved at %s and host lock retained.\n' \
      "${PREFS_BACKUP}" >&2
    cleanup_status=1
  fi

  # CrashReporter can write the final .ips file after the process has exited.
  # Keep the lock held, allow a bounded grace period, then compare manifests.
  sleep 2
  if [[ -n "${CRASH_AFTER}" ]]; then
    crash_report_paths "${CRASH_AFTER}"
    record_new_crash_reports || cleanup_status=1
  fi

  if [[ -n "${PREFS_VERIFY}" ]]; then
    rm -f -- "${PREFS_VERIFY}" || true
    PREFS_VERIFY=""
  fi
  rm -f -- "${CRASH_BEFORE}" "${CRASH_AFTER}" 2>/dev/null || true
  CRASH_BEFORE=""
  CRASH_AFTER=""

  if [[ -n "${RUN_ROOT}" ]]; then
    rm -rf -- "${RUN_ROOT}" || cleanup_status=$?
    RUN_ROOT=""
  fi

  if [[ ${restore_status} -eq 0 ]]; then
    physical_runtime_lock_release || cleanup_status=$?
  fi

  if [[ "${original_status}" -ne 0 ]]; then
    exit "${original_status}"
  fi
  exit "${cleanup_status}"
}

handle_signal() {
  exit "$1"
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
    "physical_runtime_lock_mark_recovery_required",
    "Preference recovery failed",
    '"${command_line}" == "${RUN_EXECUTABLE}"',
    "defaults export",
    "defaults import",
    "verify_restored_preferences",
    "crash-report-manifest.txt",
    "CrashReporter can write the final .ips file after the process has exited",
    "Foreign MacVitals process appeared and was not terminated",
    "MACVITALS_RUN_LONG_STABILITY",
):
    if required not in text:
        raise SystemExit(f"safe physical wrapper contract is missing: {required}")
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
for command_name in awk basename defaults ditto find git pgrep ps python3 shasum sleep stat; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "required command is unavailable: ${command_name}"
done

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
  fail "existing MacVitals instance prevents physical validation"
fi

CRASH_BEFORE="$(mktemp "${TMPDIR:-/tmp}/macvitals-crash-before.XXXXXX")"
CRASH_AFTER="$(mktemp "${TMPDIR:-/tmp}/macvitals-crash-after.XXXXXX")"
crash_report_paths "${CRASH_BEFORE}"
capture_preferences

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
