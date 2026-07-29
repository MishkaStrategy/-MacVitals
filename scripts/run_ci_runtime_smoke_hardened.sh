#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANONICAL="${SCRIPT_DIR}/run_ci_runtime_smoke.sh"
HARDENED_VALIDATOR="${SCRIPT_DIR}/validate_runtime_metrics_hardened.py"
NEEDLE='python3 "${ROOT_DIR}/scripts/validate_runtime_metrics_hardened.py" \'

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

[[ -f "${CANONICAL}" && ! -L "${CANONICAL}" ]] || fail "Canonical runtime smoke script is missing or unsafe"
[[ -f "${HARDENED_VALIDATOR}" && ! -L "${HARDENED_VALIDATOR}" ]] || fail "Hardened runtime validator is missing or unsafe"

self_test() {
  python3 "${HARDENED_VALIDATOR}" --self-test
  CANONICAL="${CANONICAL}" NEEDLE="${NEEDLE}" python3 - <<'PY'
from pathlib import Path
import os

text = Path(os.environ["CANONICAL"]).read_text(encoding="utf-8")
needle = os.environ["NEEDLE"]
if text.count(needle) != 1:
    raise SystemExit("Canonical runtime smoke must invoke the hardened validator exactly once")
if "validate_runtime_metrics.py" in text.replace("validate_runtime_metrics_hardened.py", ""):
    raise SystemExit("Canonical runtime smoke still references the unhardened validator")
print("Hardened runtime smoke wrapper self-test passed")
PY
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit 0
fi

bash "${CANONICAL}" "$@"
