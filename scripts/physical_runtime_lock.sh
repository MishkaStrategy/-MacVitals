#!/usr/bin/env bash
# Shared host-level serialization for tests that launch the MacVitals process.
# Source this file, call physical_runtime_lock_acquire, and release from cleanup.

physical_runtime_lock_directory() {
  printf '%s\n' "${MACVITALS_PHYSICAL_LOCK_DIR:-/tmp/macvitals-physical-runtime.lock}"
}

physical_runtime_lock_validate_directory() {
  local lock_dir="$1"
  [[ "${lock_dir}" == /* && "${lock_dir}" == *.lock && "${lock_dir}" != *$'\n'* ]] || {
    printf 'Physical runtime lock path must be an absolute .lock path: %s\n' "${lock_dir}" >&2
    return 2
  }
  if [[ -e "${lock_dir}" || -L "${lock_dir}" ]]; then
    [[ -d "${lock_dir}" && ! -L "${lock_dir}" ]] || {
      printf 'Physical runtime lock path is not a safe directory: %s\n' "${lock_dir}" >&2
      return 2
    }
  fi
}

physical_runtime_lock_owner_pid() {
  local lock_dir="$1"
  local owner_pid=""
  if [[ -r "${lock_dir}/owner-pid" ]]; then
    IFS= read -r owner_pid < "${lock_dir}/owner-pid" || owner_pid=""
  fi
  printf '%s\n' "${owner_pid}"
}

physical_runtime_lock_process_is_alive() {
  local pid="$1"
  [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

physical_runtime_lock_age_seconds() {
  local lock_dir="$1"
  local now modified
  now="$(date +%s)"
  if modified="$(stat -f %m "${lock_dir}" 2>/dev/null)"; then
    :
  elif modified="$(stat -c %Y "${lock_dir}" 2>/dev/null)"; then
    :
  else
    printf '0\n'
    return
  fi
  if [[ "${now}" =~ ^[0-9]+$ && "${modified}" =~ ^[0-9]+$ && ${now} -ge ${modified} ]]; then
    printf '%s\n' "$((now - modified))"
  else
    printf '0\n'
  fi
}

physical_runtime_lock_write_metadata() {
  local lock_dir="$1"
  local temporary="${lock_dir}/owner-metadata.tmp.$$"
  {
    printf 'pid=%s\n' "$$"
    printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'runner_name=%s\n' "${RUNNER_NAME:-local}"
    printf 'workflow=%s\n' "${GITHUB_WORKFLOW:-local}"
    printf 'run_id=%s\n' "${GITHUB_RUN_ID:-local}"
    printf 'job=%s\n' "${GITHUB_JOB:-local}"
  } > "${temporary}"
  mv "${temporary}" "${lock_dir}/owner-metadata"
}

physical_runtime_lock_try_reclaim() {
  local lock_dir="$1"
  local owner_pid="$2"
  local stale_grace_seconds="$3"
  local stale_dir

  [[ -d "${lock_dir}" && ! -L "${lock_dir}" ]] || return 1

  if [[ "${owner_pid}" =~ ^[0-9]+$ ]]; then
    physical_runtime_lock_process_is_alive "${owner_pid}" && return 1
  else
    (( $(physical_runtime_lock_age_seconds "${lock_dir}") >= stale_grace_seconds )) || return 1
  fi

  stale_dir="${lock_dir}.stale.$$.$RANDOM"
  if mv "${lock_dir}" "${stale_dir}" 2>/dev/null; then
    rm -rf -- "${stale_dir}"
    return 0
  fi
  return 1
}

physical_runtime_lock_acquire() {
  local lock_dir timeout_seconds poll_seconds stale_grace_seconds deadline owner_pid
  lock_dir="$(physical_runtime_lock_directory)"
  physical_runtime_lock_validate_directory "${lock_dir}" || return $?
  timeout_seconds="${MACVITALS_PHYSICAL_LOCK_TIMEOUT_SECONDS:-900}"
  poll_seconds="${MACVITALS_PHYSICAL_LOCK_POLL_SECONDS:-1}"
  stale_grace_seconds="${MACVITALS_PHYSICAL_LOCK_STALE_GRACE_SECONDS:-30}"

  [[ "${timeout_seconds}" =~ ^[0-9]+$ ]] && ((timeout_seconds > 0)) || {
    printf 'Physical runtime lock timeout must be a positive integer: %s\n' "${timeout_seconds}" >&2
    return 2
  }
  [[ "${poll_seconds}" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
    printf 'Physical runtime lock poll interval must be non-negative: %s\n' "${poll_seconds}" >&2
    return 2
  }
  [[ "${stale_grace_seconds}" =~ ^[0-9]+$ ]] || {
    printf 'Physical runtime lock stale grace must be a non-negative integer: %s\n' "${stale_grace_seconds}" >&2
    return 2
  }

  if [[ "${MACVITALS_PHYSICAL_LOCK_HELD:-0}" == "1" ]]; then
    return 0
  fi

  deadline=$((SECONDS + timeout_seconds))
  while true; do
    if mkdir "${lock_dir}" 2>/dev/null; then
      printf '%s\n' "$$" > "${lock_dir}/owner-pid"
      physical_runtime_lock_write_metadata "${lock_dir}"
      MACVITALS_PHYSICAL_LOCK_HELD=1
      export MACVITALS_PHYSICAL_LOCK_HELD
      printf 'Acquired physical runtime lock: %s (pid=%s)\n' "${lock_dir}" "$$"
      return 0
    fi

    owner_pid="$(physical_runtime_lock_owner_pid "${lock_dir}")"
    if [[ "${owner_pid}" == "$$" ]]; then
      MACVITALS_PHYSICAL_LOCK_HELD=1
      export MACVITALS_PHYSICAL_LOCK_HELD
      return 0
    fi
    if physical_runtime_lock_try_reclaim "${lock_dir}" "${owner_pid}" "${stale_grace_seconds}"; then
      continue
    fi

    if ((SECONDS >= deadline)); then
      printf 'Physical runtime lock remained busy for %ss: %s (owner_pid=%s)\n' \
        "${timeout_seconds}" "${lock_dir}" "${owner_pid:-unknown}" >&2
      return 1
    fi
    sleep "${poll_seconds}"
  done
}

physical_runtime_lock_release() {
  local lock_dir owner_pid
  [[ "${MACVITALS_PHYSICAL_LOCK_HELD:-0}" == "1" ]] || return 0
  lock_dir="$(physical_runtime_lock_directory)"
  if ! physical_runtime_lock_validate_directory "${lock_dir}"; then
    MACVITALS_PHYSICAL_LOCK_HELD=0
    export MACVITALS_PHYSICAL_LOCK_HELD
    return 2
  fi
  owner_pid="$(physical_runtime_lock_owner_pid "${lock_dir}")"
  if [[ "${owner_pid}" == "$$" ]]; then
    rm -rf -- "${lock_dir}"
    printf 'Released physical runtime lock: %s (pid=%s)\n' "${lock_dir}" "$$"
  else
    printf 'Refusing to release physical runtime lock owned by pid %s\n' \
      "${owner_pid:-unknown}" >&2
  fi
  MACVITALS_PHYSICAL_LOCK_HELD=0
  export MACVITALS_PHYSICAL_LOCK_HELD
}

physical_runtime_lock_self_test() {
  local helper_path temp_root lock_dir ready_file holder_pid
  helper_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/macvitals-physical-lock-test.XXXXXX")"
  lock_dir="${temp_root}/runtime.lock"
  ready_file="${temp_root}/ready"
  holder_pid=""

  cleanup_self_test() {
    if [[ -n "${holder_pid}" ]] && kill -0 "${holder_pid}" 2>/dev/null; then
      kill -TERM "${holder_pid}" 2>/dev/null || true
      wait "${holder_pid}" 2>/dev/null || true
    fi
    rm -rf -- "${temp_root}"
  }
  trap cleanup_self_test EXIT INT TERM

  MACVITALS_PHYSICAL_LOCK_DIR="${temp_root}/unsafe"
  MACVITALS_PHYSICAL_LOCK_HELD=0
  if physical_runtime_lock_acquire; then
    printf '%s\n' 'Unsafe lock path unexpectedly passed validation' >&2
    return 1
  fi

  mkdir "${temp_root}/target"
  ln -s "${temp_root}/target" "${temp_root}/symlink.lock"
  MACVITALS_PHYSICAL_LOCK_DIR="${temp_root}/symlink.lock"
  if physical_runtime_lock_acquire; then
    printf '%s\n' 'Symlink lock path unexpectedly passed validation' >&2
    return 1
  fi

  MACVITALS_PHYSICAL_LOCK_DIR="${lock_dir}"
  MACVITALS_PHYSICAL_LOCK_TIMEOUT_SECONDS=2
  MACVITALS_PHYSICAL_LOCK_POLL_SECONDS=0.1
  MACVITALS_PHYSICAL_LOCK_STALE_GRACE_SECONDS=0
  MACVITALS_PHYSICAL_LOCK_HELD=0
  physical_runtime_lock_acquire
  [[ "$(physical_runtime_lock_owner_pid "${lock_dir}")" == "$$" ]]
  physical_runtime_lock_release
  [[ ! -e "${lock_dir}" ]]

  MACVITALS_PHYSICAL_LOCK_DIR="${lock_dir}" READY_FILE="${ready_file}" HELPER_PATH="${helper_path}" \
    bash -c '
      set -euo pipefail
      source "${HELPER_PATH}"
      export MACVITALS_PHYSICAL_LOCK_DIR
      export MACVITALS_PHYSICAL_LOCK_TIMEOUT_SECONDS=2
      export MACVITALS_PHYSICAL_LOCK_POLL_SECONDS=0.1
      export MACVITALS_PHYSICAL_LOCK_STALE_GRACE_SECONDS=0
      physical_runtime_lock_acquire
      trap physical_runtime_lock_release EXIT INT TERM
      : > "${READY_FILE}"
      sleep 5
    ' &
  holder_pid=$!
  for _ in {1..50}; do
    [[ -f "${ready_file}" ]] && break
    sleep 0.1
  done
  [[ -f "${ready_file}" ]]

  MACVITALS_PHYSICAL_LOCK_HELD=0
  MACVITALS_PHYSICAL_LOCK_TIMEOUT_SECONDS=1
  if physical_runtime_lock_acquire; then
    printf '%s\n' 'Second owner unexpectedly acquired a live physical runtime lock' >&2
    return 1
  fi
  [[ -d "${lock_dir}" ]]

  kill -TERM "${holder_pid}" 2>/dev/null || true
  wait "${holder_pid}" 2>/dev/null || true
  holder_pid=""
  for _ in {1..50}; do
    [[ ! -e "${lock_dir}" ]] && break
    sleep 0.1
  done
  [[ ! -e "${lock_dir}" ]]

  mkdir "${lock_dir}"
  printf '99999999\n' > "${lock_dir}/owner-pid"
  MACVITALS_PHYSICAL_LOCK_TIMEOUT_SECONDS=2
  MACVITALS_PHYSICAL_LOCK_HELD=0
  physical_runtime_lock_acquire
  [[ "$(physical_runtime_lock_owner_pid "${lock_dir}")" == "$$" ]]
  physical_runtime_lock_release

  trap - EXIT INT TERM
  cleanup_self_test
  printf '%s\n' 'Physical runtime lock self-test passed'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    --self-test)
      physical_runtime_lock_self_test
      ;;
    *)
      printf 'Usage: %s --self-test\n' "$0" >&2
      exit 2
      ;;
  esac
fi
