#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAFE_WRAPPER="${SCRIPT_DIR}/run_safe_physical_validation.sh"
SAME_SESSION_RUNNER="${SCRIPT_DIR}/run_ci_physical_validation_same_session.sh"
TEMP_WRAPPER=""

fail() {
  printf 'safe-same-session-physical-validation: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  [[ -z "${TEMP_WRAPPER}" ]] || rm -f -- "${TEMP_WRAPPER}"
}
trap cleanup EXIT HUP INT TERM

for path in "${SAFE_WRAPPER}" "${SAME_SESSION_RUNNER}"; do
  [[ -f "${path}" && ! -L "${path}" ]] || fail "required validation wrapper is missing or unsafe: ${path}"
done

materialize_wrapper() {
  local target="$1"
  python3 - "${SAFE_WRAPPER}" "${target}" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
text = source.read_text(encoding="utf-8")
old = 'RUNNER="${ROOT_DIR}/scripts/run_ci_physical_validation_hardened.sh"'
new = 'RUNNER="${ROOT_DIR}/scripts/run_ci_physical_validation_same_session.sh"'
if text.count(old) != 1:
    raise SystemExit("recovery-safe wrapper runner assignment is not uniquely patchable")
text = text.replace(old, new)
target.write_text(text, encoding="utf-8")
PY
  chmod 700 "${target}"
}

self_test() {
  bash "${SAME_SESSION_RUNNER}" --self-test
  TEMP_WRAPPER="${SCRIPT_DIR}/.run_safe_physical_validation_same_session.selftest.$$.sh"
  materialize_wrapper "${TEMP_WRAPPER}"
  bash -n "${TEMP_WRAPPER}"
  bash "${TEMP_WRAPPER}" --self-test
  rm -f -- "${TEMP_WRAPPER}"
  TEMP_WRAPPER=""
  printf '%s\n' 'Recovery-safe same-session physical wrapper self-test passed'
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit 0
fi

[[ $# -eq 3 ]] || fail "usage: $0 <version> <MacVitals.app> <expected-commit-sha>"
TEMP_WRAPPER="${SCRIPT_DIR}/.run_safe_physical_validation_same_session.$$.sh"
materialize_wrapper "${TEMP_WRAPPER}"
bash -n "${TEMP_WRAPPER}"
bash "${TEMP_WRAPPER}" "$@"
