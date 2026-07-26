#!/bin/bash
# Route the canonical physical runner through the conservative hardened harness.
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORIGINAL="${SCRIPT_DIR}/run_ci_physical_validation.sh"
HARDENED="${SCRIPT_DIR}/run_physical_validation_hardened.py"
XCRUN_SHIM="${SCRIPT_DIR}/xcrun_physical_hardened.sh"
TEMP_RUNNER=""
SHIM_ROOT=""

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

cleanup() {
  [[ -z "${TEMP_RUNNER}" ]] || rm -f -- "${TEMP_RUNNER}"
  [[ -z "${SHIM_ROOT}" ]] || rm -rf -- "${SHIM_ROOT}"
}
trap cleanup EXIT HUP INT TERM

for path in "${ORIGINAL}" "${HARDENED}" "${XCRUN_SHIM}"; do
  [[ -f "${path}" && ! -L "${path}" ]] || fail "Required hardened physical runner file is missing or unsafe: ${path}"
done

build_hardened_runner() {
  local target="$1"
  python3 - "${ORIGINAL}" "${target}" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
text = source.read_text(encoding="utf-8")

replacements = (
    (
        'HARNESS="${REPOSITORY}/scripts/run_physical_validation.py"',
        'HARNESS="${REPOSITORY}/scripts/run_physical_validation_hardened.py"',
        "harness assignment",
    ),
    (
        'module.host_snapshot()',
        'module.base.host_snapshot()',
        "canonical host snapshot delegation",
    ),
    (
        'record_instrument "Energy Log" "energy-log" 300',
        '''if grep -Fq "Energy Log" "${TEMP_APP_ROOT}/templates.raw.txt"; then
  record_instrument "Energy Log" "energy-log" 300
elif grep -Fq "Power Profiler" "${TEMP_APP_ROOT}/templates.raw.txt"; then
  record_instrument "Power Profiler" "energy-log" 300
else
  record_instrument "Energy Log" "energy-log" 300
fi''',
        "energy template fallback",
    ),
)
for old, new, label in replacements:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Canonical runner {label} is not uniquely patchable: {count}")
    text = text.replace(old, new)

target.write_text(text, encoding="utf-8")
PY
  chmod 700 "${target}"
}

validate_importlib_loading() {
  PYTHONPATH="${SCRIPT_DIR}" PYTHONNOUSERSITE=1 python3 - "${HARDENED}" <<'PY'
from pathlib import Path
import importlib.util
import sys

path = Path(sys.argv[1]).resolve()
spec = importlib.util.spec_from_file_location("macvitals_hardened_import_regression", path)
if spec is None or spec.loader is None:
    raise SystemExit("Could not construct hardened harness import spec")
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
expected = path.with_name("run_physical_validation.py")
actual = Path(module.base.__file__).resolve()
if actual != expected:
    raise SystemExit(f"Hardened harness imported unexpected base module: {actual}")
if not callable(getattr(module.base, "host_snapshot", None)):
    raise SystemExit("Canonical host snapshot is unavailable through hardened base")
print("Hardened harness importlib regression self-test passed")
PY
}

self_test() {
  bash "${ORIGINAL}" --self-test
  python3 "${HARDENED}" self-test
  bash "${XCRUN_SHIM}" --self-test
  validate_importlib_loading

  TEMP_RUNNER="${SCRIPT_DIR}/.run_ci_physical_validation_hardened.selftest.$$.sh"
  build_hardened_runner "${TEMP_RUNNER}"
  bash -n "${TEMP_RUNNER}"
  python3 - "${TEMP_RUNNER}" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
for required in (
    'run_physical_validation_hardened.py',
    'module.base.host_snapshot()',
    'record_instrument "Power Profiler" "energy-log" 300',
):
    if required not in text:
        raise SystemExit(f"Hardened physical runner patch is missing: {required}")
print("Hardened physical runner wrapper self-test passed")
PY
  rm -f -- "${TEMP_RUNNER}"
  TEMP_RUNNER=""
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit 0
fi

REAL_XCRUN="$(command -v xcrun || true)"
[[ -n "${REAL_XCRUN}" && -x "${REAL_XCRUN}" ]] || fail "Real xcrun is unavailable"
SHIM_ROOT="$(mktemp -d /private/tmp/macvitals-xcrun-shim.XXXXXX)"
/bin/cp "${XCRUN_SHIM}" "${SHIM_ROOT}/xcrun"
chmod 700 "${SHIM_ROOT}/xcrun"

TEMP_RUNNER="${SCRIPT_DIR}/.run_ci_physical_validation_hardened.$$.sh"
build_hardened_runner "${TEMP_RUNNER}"
PATH="${SHIM_ROOT}:${PATH}" \
PYTHONPATH="${SCRIPT_DIR}" \
PYTHONNOUSERSITE=1 \
MACVITALS_REAL_XCRUN="${REAL_XCRUN}" \
  bash "${TEMP_RUNNER}" "$@"
