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

process_cleanup = r'''candidate_pid_is_owned() {
  local pid="$1"
  local command_line
  [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
  kill -0 "${pid}" 2>/dev/null || return 1
  command_line="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
  [[ "${command_line}" == "${EXECUTABLE}" || "${command_line}" == "${EXECUTABLE} "* ]]
}

terminate_exact_candidate_processes() {
  local pid
  local remaining=()
  while IFS= read -r pid; do
    candidate_pid_is_owned "${pid}" && remaining+=("${pid}")
  done < <(pgrep -x MacVitals 2>/dev/null || true)

  for pid in "${remaining[@]}"; do
    if candidate_pid_is_owned "${pid}"; then
      kill -TERM "${pid}" 2>/dev/null || true
    fi
  done
  if [[ ${#remaining[@]} -eq 0 ]]; then
    return 0
  fi
  local attempt
  for attempt in {1..20}; do
    local alive=0
    for pid in "${remaining[@]}"; do
      candidate_pid_is_owned "${pid}" && alive=1
    done
    [[ ${alive} -eq 0 ]] && return 0
    sleep 0.25
  done
  for pid in "${remaining[@]}"; do
    if candidate_pid_is_owned "${pid}"; then
      kill -KILL "${pid}" 2>/dev/null || true
    fi
  done
}

'''

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
        'cd "${REPOSITORY}"',
        process_cleanup + 'cd "${REPOSITORY}"',
        "exact-candidate process cleanup function",
    ),
    (
        '''  printf 'Running physical scenario %s for %s seconds at %s-second interval\\n' "${scenario}" "${duration}" "${interval}"
  if ! gui_exec caffeinate''',
        '''  printf 'Running physical scenario %s for %s seconds at %s-second interval\\n' "${scenario}" "${duration}" "${interval}"
  terminate_exact_candidate_processes
  if ! gui_exec caffeinate''',
        "scenario process cleanup",
    ),
    (
        '''  printf 'Running physical scenario stability-six-hour for 21600 seconds with %s-second external-power monitoring\\n' "${poll_seconds}"

  set +e''',
        '''  printf 'Running physical scenario stability-six-hour for 21600 seconds with %s-second external-power monitoring\\n' "${poll_seconds}"
  terminate_exact_candidate_processes

  set +e''',
        "stability process cleanup",
    ),
    (
        '''STABILITY_FACTS="$(power_facts)"
STABILITY_SOURCE="$(printf '%s\\n' "${STABILITY_FACTS}" | sed -n '1p')"
if [[ "${STABILITY_SOURCE}" == "AC Power" || "${STABILITY_SOURCE}" == Adapter* ]]; then
  run_stability_scenario
else
  python3 "${HARNESS}" review \\
    --session "${SESSION}" \\
    --scenario "stability-six-hour" \\
    --status "not-tested" \\
    --note "Six-hour stability requires external power; skipped to prevent battery depletion"
  printf 'Six-hour stability requires external power; current source is %s\\n' "${STABILITY_SOURCE}" >&2
  REQUIRED_SCENARIO_GAPS=$((REQUIRED_SCENARIO_GAPS + 1))
fi''',
        '''LONG_STABILITY_MODE="${MACVITALS_RUN_LONG_STABILITY:-0}"
case "${LONG_STABILITY_MODE}" in
  0|1) ;;
  *) fail "MACVITALS_RUN_LONG_STABILITY must be 0 or 1" ;;
esac
if [[ "${LONG_STABILITY_MODE}" == "1" ]]; then
  STABILITY_FACTS="$(power_facts)"
  STABILITY_SOURCE="$(printf '%s\\n' "${STABILITY_FACTS}" | sed -n '1p')"
  if [[ "${STABILITY_SOURCE}" == "AC Power" || "${STABILITY_SOURCE}" == Adapter* ]]; then
    run_stability_scenario
  else
    python3 "${HARNESS}" review \\
      --session "${SESSION}" \\
      --scenario "stability-six-hour" \\
      --status "not-tested" \\
      --note "Six-hour stability requires external power; skipped to prevent battery depletion"
    printf 'Six-hour stability requires external power; current source is %s\\n' "${STABILITY_SOURCE}" >&2
    REQUIRED_SCENARIO_GAPS=$((REQUIRED_SCENARIO_GAPS + 1))
  fi
else
  python3 "${HARNESS}" review \\
    --session "${SESSION}" \\
    --scenario "stability-six-hour" \\
    --status "not-tested" \\
    --note "Six-hour stability is opt-in and is not part of the bounded pull-request physical run"
  printf '%s\\n' 'Six-hour stability is opt-in; bounded physical validation continues without it'
fi''',
        "long stability opt-in",
    ),
    (
        '''  set +e
  gui_exec env HOME="${TRACE_HOME}" LC_ALL=C LANG=C xcrun xctrace record''',
        '''  terminate_exact_candidate_processes
  set +e
  gui_exec env HOME="${TRACE_HOME}" LC_ALL=C LANG=C xcrun xctrace record''',
        "Instruments process cleanup",
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
    (
        '''  if [[ ${all_collected} -eq 1 ]]; then
    python3 "${HARNESS}" manual \\
      --session "${SESSION}" \\
      --gate "${gate}" \\
      --status "pending-review" \\
      --note "${description} collected locally with SHA-256; human review required"
  else
    python3 "${HARNESS}" manual \\
      --session "${SESSION}" \\
      --gate "${gate}" \\
      --status "not-tested" \\
      --note "${description} incomplete: ${details}"
    INSTRUMENT_GAPS=$((INSTRUMENT_GAPS + 1))
  fi''',
        '''  if [[ ${all_collected} -eq 1 ]]; then
    python3 "${HARNESS}" manual \\
      --session "${SESSION}" \\
      --gate "${gate}" \\
      --status "pending-review" \\
      --note "${description} collected locally with SHA-256; human review required"
  elif [[ "${gate}" == "instrumentsEnergy" && "$(instrument_status "energy-log")" == "failed(exit=2)" && -f "${INSTRUMENTS_SESSION}/energy-log.log" && ! -L "${INSTRUMENTS_SESSION}/energy-log.log" ]] && grep -Fq "The Power Profiler instrument is not supported on macOS." "${INSTRUMENTS_SESSION}/energy-log.log"; then
    python3 "${HARNESS}" manual \\
      --session "${SESSION}" \\
      --gate "${gate}" \\
      --status "not-tested" \\
      --note "Power Profiler is unsupported on macOS; the Instruments energy gate remains open without failing physical collection"
    printf '%s\\n' 'Power Profiler unsupported on macOS; Instruments energy gate remains not-tested'
  else
    python3 "${HARNESS}" manual \\
      --session "${SESSION}" \\
      --gate "${gate}" \\
      --status "not-tested" \\
      --note "${description} incomplete: ${details}"
    INSTRUMENT_GAPS=$((INSTRUMENT_GAPS + 1))
  fi''',
        "macOS Power Profiler unsupported classification",
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
  python3 - "${TEMP_RUNNER}" "$0" <<'PY'
from pathlib import Path
import sys

runner = Path(sys.argv[1]).read_text(encoding="utf-8")
wrapper = Path(sys.argv[2]).read_text(encoding="utf-8")
for required in (
    'run_physical_validation_hardened.py',
    'module.base.host_snapshot()',
    'record_instrument "Power Profiler" "energy-log" 300',
    'candidate_pid_is_owned()',
    'terminate_exact_candidate_processes()',
    '"${command_line}" == "${EXECUTABLE}"',
    'candidate_pid_is_owned "${pid}"',
    'MACVITALS_RUN_LONG_STABILITY',
    'Six-hour stability is opt-in',
    'The Power Profiler instrument is not supported on macOS.',
    'Power Profiler unsupported on macOS; Instruments energy gate remains not-tested',
):
    if required not in runner:
        raise SystemExit(f"Hardened physical runner patch is missing: {required}")
if runner.count('terminate_exact_candidate_processes\n') < 3:
    raise SystemExit("Exact-candidate process cleanup is not applied to all automated launch paths")
if runner.count('candidate_pid_is_owned "${pid}"') < 4:
    raise SystemExit("Exact-candidate PID ownership is not revalidated across cleanup phases")
if 'GITHUB_SHA="${EXPECTED_SHA}"' not in wrapper:
    raise SystemExit("Hardened wrapper does not bind child verification to the exact checkout SHA")
print("Hardened physical runner wrapper self-test passed")
PY
  rm -f -- "${TEMP_RUNNER}"
  TEMP_RUNNER=""
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit 0
fi

[[ $# -eq 3 ]] || fail "Usage: $0 <version> <MacVitals.app> <expected-commit-sha>"
EXPECTED_SHA="$3"
[[ "${EXPECTED_SHA}" =~ ^[0-9a-f]{40}$ ]] || fail "Expected commit must be a full lowercase SHA-1"

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
GITHUB_SHA="${EXPECTED_SHA}" \
  bash "${TEMP_RUNNER}" "$@"
