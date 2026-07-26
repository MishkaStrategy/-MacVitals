#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGINAL="${SCRIPT_DIR}/run_ci_runtime_smoke.sh"
HARDENED_VALIDATOR="${SCRIPT_DIR}/validate_runtime_metrics_hardened.py"
NEEDLE='python3 "${ROOT_DIR}/scripts/validate_runtime_metrics.py" \'
REPLACEMENT='python3 "${ROOT_DIR}/scripts/validate_runtime_metrics_hardened.py" \'

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

[[ -f "${ORIGINAL}" && ! -L "${ORIGINAL}" ]] || fail "Canonical runtime smoke script is missing or unsafe"
[[ -f "${HARDENED_VALIDATOR}" && ! -L "${HARDENED_VALIDATOR}" ]] || fail "Hardened runtime validator is missing or unsafe"

self_test() {
  python3 "${HARDENED_VALIDATOR}" --self-test
  ORIGINAL="${ORIGINAL}" NEEDLE="${NEEDLE}" python3 - <<'PY'
from pathlib import Path
import os

text = Path(os.environ["ORIGINAL"]).read_text(encoding="utf-8")
needle = os.environ["NEEDLE"]
if text.count(needle) != 1:
    raise SystemExit("Canonical runtime validator invocation is not uniquely patchable")
print("Hardened runtime smoke wrapper self-test passed")
PY
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit 0
fi

TEMP_SCRIPT="${SCRIPT_DIR}/.run_ci_runtime_smoke_hardened.$$.sh"
cleanup() {
  rm -f -- "${TEMP_SCRIPT}"
}
trap cleanup EXIT HUP INT TERM

ORIGINAL="${ORIGINAL}" TEMP_SCRIPT="${TEMP_SCRIPT}" NEEDLE="${NEEDLE}" REPLACEMENT="${REPLACEMENT}" python3 - <<'PY'
from pathlib import Path
import os

source = Path(os.environ["ORIGINAL"])
target = Path(os.environ["TEMP_SCRIPT"])
text = source.read_text(encoding="utf-8")
needle = os.environ["NEEDLE"]
replacement = os.environ["REPLACEMENT"]
if text.count(needle) != 1:
    raise SystemExit("Canonical runtime validator invocation is not uniquely patchable")
target.write_text(text.replace(needle, replacement), encoding="utf-8")
PY
chmod 700 "${TEMP_SCRIPT}"
bash "${TEMP_SCRIPT}" "$@"
