#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_HELPER="${ROOT_DIR}/scripts/physical_runtime_lock.sh"
RUNNER="${ROOT_DIR}/scripts/run_ci_physical_validation_hardened.sh"
RECOVERY_GUARD="${ROOT_DIR}/scripts/physical_preference_recovery_guard.py"
DOMAIN="com.mishkacher.MacVitals"
EVIDENCE_ROOT="${ROOT_DIR}/physical-validation-results"
RUN_ROOT=""
RUN_APP=""
RUN_EXECUTABLE=""
CRASH_BEFORE=""
CRASH_AFTER=""
LOCK_HELD=0
RECOVERY_CAPTURED=0
RECOVERY_SENTINEL=0

fail() {
  printf 'safe-physical-validation: %s\n' "$*" >&2
  exit 1
}

for path in "${LOCK_HELPER}" "${RUNNER}" "${RECOVERY_GUARD}"; do
  [[ -f "${path}" && ! -L "${path}" ]] || fail "required safety helper is missing or unsafe: ${path}"
done
# shellcheck source=physical_runtime_lock.sh
source "${LOCK_HELPER}"

recover_interrupted_preferences() {
  local lock_dir sentinel owner_pid message stale_domain stale_token confirmed_message
  lock_dir="$(physical_runtime_lock_directory)"
  if [[ ! -e "${lock_dir}" && ! -L "${lock_dir}" ]]; then
    return 0
  fi
  physical_runtime_lock_validate_directory "${lock_dir}" || fail "existing physical runtime lock is unsafe"
  sentinel="${lock_dir}/preferences-recovery-required"
  if [[ ! -e "${sentinel}" && ! -L "${sentinel}" ]]; then
    return 0
  fi
  [[ -f "${sentinel}" && ! -L "${sentinel}" ]] || fail "preference recovery sentinel is unsafe"

  owner_pid="$(physical_runtime_lock_owner_pid "${lock_dir}")"
  if [[ "${owner_pid}" =~ ^[0-9]+$ ]] && physical_runtime_lock_process_is_alive "${owner_pid}"; then
    fail "preference recovery lock still has a live owner pid ${owner_pid}"
  fi
  if pgrep -x MacVitals >/dev/null 2>&1; then
    fail "preference recovery is required but a MacVitals process is running"
  fi

  message=""
  IFS= read -r message < "${sentinel}" || fail "could not read preference recovery sentinel"
  if [[ "${message}" =~ ^domain=([A-Za-z0-9.-]+)[[:space:]]token=([A-Za-z0-9._-]+)[[:space:]]recovery=pending$ ]]; then
    stale_domain="${BASH_REMATCH[1]}"
    stale_token="${BASH_REMATCH[2]}"
  else
    fail "preference recovery sentinel identity is invalid"
  fi
  [[ "${stale_domain}" == "${DOMAIN}" ]] || fail "preference recovery sentinel domain is unexpected"

  python3 "${RECOVERY_GUARD}" restore \
    --domain "${stale_domain}" \
    --token "${stale_token}"

  if pgrep -x MacVitals >/dev/null 2>&1; then
    fail "MacVitals appeared during preference recovery; stale lock is retained"
  fi
  confirmed_message=""
  IFS= read -r confirmed_message < "${sentinel}" || fail "could not re-read preference recovery sentinel"
  [[ "${confirmed_message}" == "${message}" ]] || fail "preference recovery sentinel changed during restore"

  rm -f -- "${sentinel}" || fail "could not clear restored preference recovery sentinel"
  if ! physical_runtime_lock_try_reclaim "${lock_dir}" "${owner_pid}" 0; then
    fail "restored stale physical runtime lock could not be reclaimed"
  fi
  printf 'Recovered interrupted physical validation preferences: token=%s\n' "${stale_token}"
}

run_pid_is_owned() {
  local pid="$1" command_line
  [[ -n "${RUN_EXECUTABLE}" && "${pid}" =~ ^[0-9]+$ ]] || return 1
  kill -0 "${pid}" 2>/dev/null || return 1
  command_line="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
  [[ "${command_line}" == "${RUN_EXECUTABLE}" || "${command_line}" == "${RUN_EXECUTABLE} "* ]]
}

matching_run_pids() {
  local pid
  [[ -n "${RUN_EXECUTABLE}" ]] || return 0
  while IFS= read -r pid; do
    run_pid_is_owned "${pid}" && printf '%s\n' "${pid}"
  done < <(pgrep -x MacVitals 2>/dev/null || true)
}

terminate_unique_run_processes() {
  local pid alive pids=""
  while IFS= read -r pid; do
    [[ -n "${pid}" ]] && pids="${pids}${pid}"$'\n'
  done < <(matching_run_pids)
  [[ -n "${pids}" ]] || return 0

  while IFS= read -r pid; do
    [[ -n "${pid}" ]] || continue
    if run_pid_is_owned "${pid}"; then
      kill -TERM "${pid}" 2>/dev/null || true
    fi
  done <<< "${pids}"

  for _ in {1..40}; do
    alive=0
    while IFS= read -r pid; do
      [[ -n "${pid}" ]] || continue
      run_pid_is_owned "${pid}" && alive=1
    done <<< "${pids}"
    [[ ${alive} -eq 0 ]] && break
    sleep 0.25
  done

  while IFS= read -r pid; do
    [[ -n "${pid}" ]] || continue
    if run_pid_is_owned "${pid}"; then
      kill -KILL "${pid}" 2>/dev/null || true
    fi
  done <<< "${pids}"
}

remaining_macvitals_count() {
  local pid command_line count=0
  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    command_line="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
    [[ -n "${command_line}" ]] || continue
    if [[ -n "${RUN_EXECUTABLE}" && ( "${command_line}" == "${RUN_EXECUTABLE}" || "${command_line}" == "${RUN_EXECUTABLE} "* ) ]]; then
      printf 'Owned MacVitals process remained after cleanup: pid=%s command=%s\n' "${pid}" "${command_line}" >&2
    else
      printf 'Foreign MacVitals process appeared and was not terminated: pid=%s command=%s\n' "${pid}" "${command_line}" >&2
    fi
    count=$((count + 1))
  done < <(pgrep -x MacVitals 2>/dev/null || true)
  printf '%s\n' "${count}"
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

restore_preferences() {
  [[ ${RECOVERY_CAPTURED} -eq 1 ]] || return 0
  python3 "${RECOVERY_GUARD}" restore \
    --domain "${DOMAIN}" \
    --token "${RECOVERY_TOKEN}"
  RECOVERY_CAPTURED=0
}

cleanup() {
  local original_status="$?"
  local cleanup_status=0 remaining=0 restore_status=0
  trap - EXIT HUP INT TERM
  set +e

  terminate_unique_run_processes || cleanup_status=1
  remaining="$(remaining_macvitals_count)"

  sleep 2
  if [[ -n "${CRASH_AFTER}" ]]; then
    crash_report_paths "${CRASH_AFTER}"
    record_new_crash_reports || cleanup_status=1
  fi

  if [[ ${RECOVERY_CAPTURED} -eq 1 ]]; then
    if [[ "${remaining}" == "0" ]]; then
      restore_preferences || restore_status=$?
      if [[ ${restore_status} -eq 0 && ${RECOVERY_SENTINEL} -eq 1 ]]; then
        if physical_runtime_lock_clear_recovery_required; then
          RECOVERY_SENTINEL=0
        else
          cleanup_status=1
        fi
      elif [[ ${restore_status} -ne 0 ]]; then
        cleanup_status=1
      fi
    else
      printf '%s\n' 'Preferences were not auto-restored while a MacVitals process remains; durable backup and recovery sentinel are retained.' >&2
      cleanup_status=1
    fi
  fi

  rm -f -- "${CRASH_BEFORE}" "${CRASH_AFTER}" 2>/dev/null || true
  CRASH_BEFORE=""
  CRASH_AFTER=""

  if [[ -n "${RUN_ROOT}" ]]; then
    rm -rf -- "${RUN_ROOT}" || cleanup_status=1
    RUN_ROOT=""
  fi

  if [[ ${LOCK_HELD} -eq 1 ]]; then
    if [[ ${RECOVERY_SENTINEL} -eq 0 ]]; then
      if physical_runtime_lock_release; then
        LOCK_HELD=0
      else
        cleanup_status=1
      fi
    else
      printf '%s\n' 'Physical runtime lock retained because preference recovery remains required.' >&2
      cleanup_status=1
    fi
  fi

  if [[ ${original_status} -ne 0 ]]; then
    exit "${original_status}"
  fi
  exit "${cleanup_status}"
}

handle_signal() {
  exit "$1"
}

self_test() {
  bash -n "${LOCK_HELPER}" "${RUNNER}" "$0"
  python3 -m py_compile "${RECOVERY_GUARD}"
  python3 "${RECOVERY_GUARD}" self-test
  bash "${LOCK_HELPER}" --self-test
  bash "${RUNNER}" --self-test
  python3 - "$0" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
self_test_start = text.find("\nself_test() {\n")
dispatch_start = text.find('\nif [[ "${1:-}" == "--self-test" ]]; then\n', self_test_start)
if self_test_start < 0 or dispatch_start < 0 or dispatch_start <= self_test_start:
    raise SystemExit("safe physical wrapper self-test scope markers are missing or invalid")
runtime_text = text[:self_test_start] + text[dispatch_start:]
for forbidden in (
    "pkill",
    "killall MacVitals",
    "kill -TERM $(pgrep",
    "kill -KILL $(pgrep",
    "materialize_safe_hardened_runner",
    ".run_ci_physical_validation_hardened.safe",
):
    if forbidden in runtime_text:
        raise SystemExit(f"forbidden wrapper behavior: {forbidden}")
for required in (
    "recover_interrupted_preferences",
    "physical_runtime_lock_try_reclaim",
    "preference recovery lock still has a live owner",
    "physical_runtime_lock_acquire",
    "physical_runtime_lock_mark_recovery_required",
    "physical_runtime_lock_clear_recovery_required",
    "run_pid_is_owned",
    '"${command_line}" == "${RUN_EXECUTABLE}"',
    "terminate_unique_run_processes",
    "Foreign MacVitals process appeared and was not terminated",
    "durable backup and recovery sentinel are retained",
    'bash "${RUNNER}" "${VERSION}" "${RUN_APP}" "${EXPECTED_SHA}"',
    "physical_preference_recovery_guard.py",
    "crash-report-manifest.txt",
):
    if required not in runtime_text:
        raise SystemExit(f"safe physical wrapper contract is missing: {required}")
print("Recovery-safe canonical physical wrapper self-test passed")
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
RECOVERY_TOKEN="${RECOVERY_TOKEN:-}"
[[ "${VERSION}" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] || fail "version must contain one to three numeric components"
[[ "${EXPECTED_SHA}" =~ ^[0-9a-f]{40}$ ]] || fail "expected commit must be a full lowercase SHA-1"
[[ "${RECOVERY_TOKEN}" =~ ^[A-Za-z0-9._-]+$ ]] || fail "RECOVERY_TOKEN is missing or unsafe"
[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || fail "native Apple Silicon macOS is required"
[[ -d "${APP_INPUT}" && ! -L "${APP_INPUT}" ]] || fail "input app is missing or unsafe"
[[ "$(git -C "${ROOT_DIR}" rev-parse HEAD)" == "${EXPECTED_SHA}" ]] || fail "checkout does not match expected SHA"

for command_name in awk basename comm ditto find git grep pgrep ps python3 shasum sleep stat; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "required command is unavailable: ${command_name}"
done

trap cleanup EXIT
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM
trap 'handle_signal 129' HUP

recover_interrupted_preferences
physical_runtime_lock_acquire
LOCK_HELD=1

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

python3 "${RECOVERY_GUARD}" capture \
  --domain "${DOMAIN}" \
  --token "${RECOVERY_TOKEN}"
RECOVERY_CAPTURED=1
physical_runtime_lock_mark_recovery_required \
  "domain=${DOMAIN} token=${RECOVERY_TOKEN} recovery=pending"
RECOVERY_SENTINEL=1

if pgrep -x MacVitals >/dev/null 2>&1; then
  fail "MacVitals appeared after durable preference capture; validation will preserve recovery state"
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
[[ -f "${RUN_EXECUTABLE}" && ! -L "${RUN_EXECUTABLE}" && -x "${RUN_EXECUTABLE}" ]] || fail "unique candidate executable is missing or unsafe"
if find "${RUN_APP}" -type l -print -quit | grep -q .; then
  fail "unique candidate app contains symbolic links"
fi

export MACVITALS_RUN_LONG_STABILITY="${MACVITALS_RUN_LONG_STABILITY:-0}"
case "${MACVITALS_RUN_LONG_STABILITY}" in
  0|1) ;;
  *) fail "MACVITALS_RUN_LONG_STABILITY must be 0 or 1" ;;
esac

bash "${RUNNER}" "${VERSION}" "${RUN_APP}" "${EXPECTED_SHA}"
