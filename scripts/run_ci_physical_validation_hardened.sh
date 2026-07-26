#!/bin/bash
# Route the canonical physical runner through the conservative hardened harness.
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORIGINAL="${SCRIPT_DIR}/run_ci_physical_validation.sh"
HARDENED="${SCRIPT_DIR}/run_physical_validation_hardened.py"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

[[ -f "${ORIGINAL}" && ! -L "${ORIGINAL}" ]] || fail "Canonical physical runner is missing or unsafe"
[[ -f "${HARDENED}" && ! -L "${HARDENED}" ]] || fail "Hardened physical harness is missing or unsafe"

self_test() {
  bash "${ORIGINAL}" --self-test
  python3 "${HARDENED}" self-test
  python3 - "${ORIGINAL}" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
needle = 'HARNESS="${REPOSITORY}/scripts/run_physical_validation.py"'
if text.count(needle) != 1:
    raise SystemExit("Canonical runner HARNESS assignment is not uniquely patchable")
print("Hardened physical runner wrapper self-test passed")
PY
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit 0
fi

TEMP_RUNNER="${SCRIPT_DIR}/.run_ci_physical_validation_hardened.$$.sh"
cleanup() {
  rm -f -- "${TEMP_RUNNER}"
}
trap cleanup EXIT HUP INT TERM

python3 - "${ORIGINAL}" "${TEMP_RUNNER}" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
text = source.read_text(encoding="utf-8")
needle = 'HARNESS="${REPOSITORY}/scripts/run_physical_validation.py"'
replacement = 'HARNESS="${REPOSITORY}/scripts/run_physical_validation_hardened.py"'
if text.count(needle) != 1:
    raise SystemExit("Canonical runner HARNESS assignment is not uniquely patchable")
target.write_text(text.replace(needle, replacement), encoding="utf-8")
PY
chmod 700 "${TEMP_RUNNER}"
bash "${TEMP_RUNNER}" "$@"
