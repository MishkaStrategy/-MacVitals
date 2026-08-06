#!/usr/bin/env bash
# Shared host-level serialization for jobs that launch MacVitals on a physical Mac.

physical_runtime_lock_directory() {
  printf '%s\n' "${MACVITALS_PHYSICAL_LOCK_DIR:-/tmp/macvitals-physical-runtime.lock}"
}

physical_runtime_lock_owner_uid() {
  local lock_dir="$1"
  if stat -f %u "${lock_dir}" 2>/dev/null; then
    return 0
  fi
  stat -c %u "${lock_dir}" 2>/dev/null
}

physical_runtime_lock_mode() {
  local lock_dir="$1"
  if stat -f %Lp "${lock_dir}" 2>/dev/null; then
    return 0
  fi
  stat -c %a "${lock_dir}" 2>/dev/null
}

physical_runtime_lock_validate_directory() {
  local lock_dir="$1"
  local owner_uid mode current_uid
  [[ "${lock_dir}" == /* && "${lock_dir}" == *.lock && "${lock_dir}" != *$'\n'* ]] || {
    printf 'Physical runtime lock path must be an absolute .lock path: %s\n' "${lock_dir}" >&2
    return 2
  }
  if [[ -e "${lock_dir}" || -L "${lock_dir}" ]]; then
    [[ -d "${lock_dir}" && ! -L "${lock_dir}" ]] || {
      printf 'Physical runtime lock path is not a safe directory: %s\n' "${lock_dir}" >&2
      return 2
    }
    current_uid="$(id -u)"
    owner_uid="$(physical_runtime_lock_owner_uid "${lock_dir}")" || {
      printf 'Could not determine physical runtime lock owner: %s\n' "${lock_dir}" >&2
      return 2
    }
    [[ "${owner_uid}" == "${current_uid}" ]] || {
      printf 'Physical runtime lock is owned by a different uid: %s\n' "${lock_dir}" >&2
      return 2
    }
    mode="$(physical_runtime_lock_mode "${lock_dir}")" || {
      printf 'Could not determine physical runtime lock permissions: %s\n' "${lock_dir}" >&2
      return 2
    }
    [[ "${mode}" =~ ^[0-7]{3,4}$ ]] || {
      printf 'Physical runtime lock permissions are invalid: %s\n' "${mode}" >&2
      return 2
    }
    (( (8#${mode} & 077) == 0 )) || {
      printf 'Physical runtime lock permissions are too broad: %s (%s)\n' "${lock_dir}" "${mode}" >&2
      return 2
    }
  fi
}

physical_runtime_lock_owner_pid() {
  local lock_dir="$1"
  local owner_pid=""
  if [[ -f "${lock_dir}/owner-pid" && ! -L "${lock_dir}/owner-pid" ]]; then
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
    printf 'attempt=%s\n' "${GITHUB_RUN_ATTEMPT:-local}"
    printf 'job=%s\n' "${GITHUB_JOB:-local}"
  } > "${temporary}"
  chmod 0600 "${temporary}"
  mv "${temporary}" "${lock_dir}/owner-metadata"
}

physical_runtime_lock_try_reclaim() {
  local lock_dir="$1"
  local owner_pid="$2"
  local stale_grace_seconds="$3"
  local stale_dir

  physical_runtime_lock_validate_directory "${lock_dir}" || return 1
  if [[ -e "${lock_dir}/preferences-recovery-required" || -L "${lock_dir}/preferences-recovery-required" ]]; then
    printf 'Physical runtime lock requires manual preference recovery: %s\n' "${lock_dir}" >&2
    return 1
  fi

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
    if mkdir -m 700 "${lock_dir}" 2>/dev/null; then
      printf '%s\n' "$$" > "${lock_dir}/owner-pid"
      chmod 0600 "${lock_dir}/owner-pid"
      physical_runtime_lock_write_metadata "${lock_dir}"
      MACVITALS_PHYSICAL_LOCK_HELD=1
      export MACVITALS_PHYSICAL_LOCK_HELD
      printf 'Acquired physical runtime lock: %s (pid=%s)\n' "${lock_dir}" "$$"
      return 0
    fi

    physical_runtime_lock_validate_directory "${lock_dir}" || return $?
    if [[ -e "${lock_dir}/preferences-recovery-required" || -L "${lock_dir}/preferences-recovery-required" ]]; then
      printf 'Physical runtime lock requires manual preference recovery: %s\n' "${lock_dir}" >&2
      return 1
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

physical_runtime_lock_mark_recovery_required() {
  local message="$1"
  local lock_dir
  [[ "${MACVITALS_PHYSICAL_LOCK_HELD:-0}" == "1" ]] || return 1
  lock_dir="$(physical_runtime_lock_directory)"
  physical_runtime_lock_validate_directory "${lock_dir}" || return $?
  [[ "$(physical_runtime_lock_owner_pid "${lock_dir}")" == "$$" ]] || return 1
  printf '%s\n' "${message}" > "${lock_dir}/preferences-recovery-required"
  chmod 0600 "${lock_dir}/preferences-recovery-required"
}

physical_runtime_lock_release() {
  local lock_dir owner_pid unexpected
  [[ "${MACVITALS_PHYSICAL_LOCK_HELD:-0}" == "1" ]] || return 0
  lock_dir="$(physical_runtime_lock_directory)"
  physical_runtime_lock_validate_directory "${lock_dir}" || return $?
  owner_pid="$(physical_runtime_lock_owner_pid "${lock_dir}")"
  [[ "${owner_pid}" == "$$" ]] || {
    printf 'Refusing to release physical runtime lock owned by pid %s\n' "${owner_pid:-unknown}" >&2
    return 1
  }
  if [[ -e "${lock_dir}/preferences-recovery-required" || -L "${lock_dir}/preferences-recovery-required" ]]; then
    printf 'Refusing to release physical runtime lock with recovery sentinel: %s\n' "${lock_dir}" >&2
    return 1
  fi

  unexpected="$(find "${lock_dir}" -mindepth 1 -maxdepth 1 \
    ! -name owner-pid ! -name owner-metadata ! -name 'owner-metadata.tmp.*' -print -quit 2>/dev/null || true)"
  [[ -z "${unexpected}" ]] || {
    printf 'Refusing to release lock with unexpected entry: %s\n' "${unexpected}" >&2
    return 1
  }

  rm -f -- "${lock_dir}/owner-pid" "${lock_dir}/owner-metadata" "${lock_dir}"/owner-metadata.tmp.*
  rmdir "${lock_dir}"
  MACVITALS_PHYSICAL_LOCK_HELD=0
  export MACVITALS_PHYSICAL_LOCK_HELD
  printf 'Released physical runtime lock: %s (pid=%s)\n' "${lock_dir}" "$$"
}

physical_runtime_lock_self_test() {
  local temp_root lock_dir target permissive_lock
  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/macvitals-lock-self-test.XXXXXX")"
  lock_dir="${temp_root}/runtime.lock"
  target="${temp_root}/target"
  permissive_lock="${temp_root}/permissive.lock"

  cleanup_lock_test() {
    MACVITALS_PHYSICAL_LOCK_HELD=0
    export MACVITALS_PHYSICAL_LOCK_HELD
    rm -rf -- "${temp_root}"
  }
  trap cleanup_lock_test EXIT INT TERM

  MACVITALS_PHYSICAL_LOCK_DIR="${temp_root}/unsafe"
  if physical_runtime_lock_acquire; then
    printf '%s\n' 'Unsafe lock path unexpectedly passed' >&2
    return 1
  fi

  mkdir "${target}"
  ln -s "${target}" "${temp_root}/symlink.lock"
  MACVITALS_PHYSICAL_LOCK_DIR="${temp_root}/symlink.lock"
  if physical_runtime_lock_acquire; then
    printf '%s\n' 'Symlink lock unexpectedly passed' >&2
    return 1
  fi

  mkdir -m 700 "${permissive_lock}"
  chmod 0755 "${permissive_lock}"
  MACVITALS_PHYSICAL_LOCK_DIR="${permissive_lock}"
  if physical_runtime_lock_acquire; then
    printf '%s\n' 'Over-permissive lock unexpectedly passed' >&2
    return 1
  fi
  rm -rf -- "${permissive_lock}"

  MACVITALS_PHYSICAL_LOCK_DIR="${lock_dir}"
  MACVITALS_PHYSICAL_LOCK_TIMEOUT_SECONDS=2
  MACVITALS_PHYSICAL_LOCK_POLL_SECONDS=0.1
  MACVITALS_PHYSICAL_LOCK_STALE_GRACE_SECONDS=0
  MACVITALS_PHYSICAL_LOCK_HELD=0
  physical_runtime_lock_acquire
  [[ "$(physical_runtime_lock_owner_pid "${lock_dir}")" == "$$" ]]
  physical_runtime_lock_release
  [[ ! -e "${lock_dir}" ]]

  mkdir -m 700 "${lock_dir}"
  printf '99999999\n' > "${lock_dir}/owner-pid"
  physical_runtime_lock_acquire
  [[ "$(physical_runtime_lock_owner_pid "${lock_dir}")" == "$$" ]]
  physical_runtime_lock_release

  mkdir -m 700 "${lock_dir}"
  printf '99999999\n' > "${lock_dir}/owner-pid"
  printf 'fixture\n' > "${lock_dir}/preferences-recovery-required"
  MACVITALS_PHYSICAL_LOCK_TIMEOUT_SECONDS=30
  MACVITALS_PHYSICAL_LOCK_HELD=0
  if physical_runtime_lock_acquire; then
    printf '%s\n' 'Recovery sentinel lock unexpectedly reclaimed' >&2
    return 1
  fi
  rm -rf -- "${lock_dir}"

  mkdir -m 700 "${lock_dir}"
  printf '99999999\n' > "${lock_dir}/owner-pid"
  MACVITALS_PHYSICAL_LOCK_HELD=1
  if physical_runtime_lock_release; then
    printf '%s\n' 'Non-owner release unexpectedly passed' >&2
    return 1
  fi

  trap - EXIT INT TERM
  cleanup_lock_test
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
