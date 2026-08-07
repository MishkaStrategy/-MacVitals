#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANONICAL_HARDENED="${SCRIPT_DIR}/run_ci_physical_validation_hardened.sh"
LAUNCHSERVICES_HARNESS="${SCRIPT_DIR}/run_physical_validation_launchservices.py"
TEMP_WRAPPER=""

fail() {
  printf 'same-session-physical-validation: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  [[ -z "${TEMP_WRAPPER}" ]] || rm -f -- "${TEMP_WRAPPER}"
}
trap cleanup EXIT HUP INT TERM

for path in "${CANONICAL_HARDENED}" "${LAUNCHSERVICES_HARNESS}"; do
  [[ -f "${path}" && ! -L "${path}" ]] || fail "required validation file is missing or unsafe: ${path}"
done

materialize_same_session_wrapper() {
  local target="$1"
  python3 - "${CANONICAL_HARDENED}" "${target}" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
text = source.read_text(encoding="utf-8")

old_harness = 'HARDENED="${SCRIPT_DIR}/run_physical_validation_hardened.py"'
new_harness = 'HARDENED="${SCRIPT_DIR}/run_physical_validation_launchservices.py"'
if text.count(old_harness) != 1:
    raise SystemExit("canonical hardened harness assignment is not uniquely patchable")
text = text.replace(old_harness, new_harness)

old_generated_harness = "        'HARNESS=\"${REPOSITORY}/scripts/run_physical_validation_hardened.py\"',\n"
new_generated_harness = "        'HARNESS=\"${REPOSITORY}/scripts/run_physical_validation_launchservices.py\"',\n"
if text.count(old_generated_harness) != 1:
    raise SystemExit("canonical generated harness assignment is not uniquely patchable")
text = text.replace(old_generated_harness, new_generated_harness)

old_required = "    'run_physical_validation_hardened.py',\n"
new_required = "    'run_physical_validation_launchservices.py',\n"
if text.count(old_required) != 1:
    raise SystemExit("canonical hardened harness self-test marker is not uniquely patchable")
text = text.replace(old_required, new_required)

for old, new, label, expected_count in (
    ('  local remaining=()\n', '  local remaining=("")\n', "Bash 3 empty-array guard", 1),
    (
        'for pid in "${remaining[@]}"; do\n',
        'for pid in "${remaining[@]}"; do\n    [[ -n "${pid}" ]] || continue\n',
        "Bash 3 sentinel skip",
        3,
    ),
    (
        'if [[ ${#remaining[@]} -eq 0 ]]; then\n',
        'if [[ ${#remaining[@]} -eq 1 ]]; then\n',
        "Bash 3 sentinel empty check",
        1,
    ),
):
    count = text.count(old)
    if count != expected_count:
        raise SystemExit(f"canonical {label} is not uniquely patchable: {count}")
    text = text.replace(old, new)

needle = "replacements = (\n"
if text.count(needle) != 1:
    raise SystemExit("canonical hardened replacement table is not uniquely patchable")

gui_replacement = r'''    (
        ''' + "'''" + r'''RUNNER_USER="$(id -un)"
RUNNER_UID="$(id -u)"
CONSOLE_USER="$(stat -f '%Su' /dev/console)"
[[ "${CONSOLE_USER}" == "${RUNNER_USER}" ]] || fail "Physical validation requires the active macOS console user"
launchctl print "gui/${RUNNER_UID}" >/dev/null || fail "Physical validation requires an active GUI launchd session"
launchctl asuser "${RUNNER_UID}" /usr/bin/true || fail "Physical validation cannot enter the active GUI bootstrap domain"

gui_exec() {
  launchctl asuser "${RUNNER_UID}" "$@"
}''' + "'''" + r''',
        ''' + "'''" + r'''RUNNER_USER="$(id -un)"
RUNNER_UID="$(id -u)"
CONSOLE_USER="$(stat -f '%Su' /dev/console)"
[[ "${CONSOLE_USER}" == "${RUNNER_USER}" ]] || fail "Physical validation requires the active macOS console user"
launchctl print "gui/${RUNNER_UID}" >/dev/null || fail "Physical validation requires an active GUI launchd session"
GUI_MANAGER_NAME="$(launchctl managername 2>/dev/null || printf 'unknown')"
GUI_MANAGER_UID="$(launchctl manageruid 2>/dev/null || printf 'unknown')"
printf 'Physical validation same-session context: console_user=%s runner_uid=%s manager=%s manager_uid=%s\n' \
  "${CONSOLE_USER}" "${RUNNER_UID}" "${GUI_MANAGER_NAME}" "${GUI_MANAGER_UID}"

gui_exec() {
  "$@"
}''' + "'''" + r''',
        "same-user GUI session execution",
    ),
'''
text = text.replace(needle, needle + gui_replacement)

self_test_print = 'print("Hardened physical runner wrapper self-test passed")'
self_test_checks = r'''if 'launchctl asuser' in runner:
    raise SystemExit("Same-session generated runner still contains launchctl asuser")
if 'gui_exec() {\n  "$@"\n}' not in runner:
    raise SystemExit("Same-session generated runner does not execute in the current user session")
if 'run_physical_validation_launchservices.py' not in runner:
    raise SystemExit("Same-session generated runner does not use the LaunchServices harness")
if 'local remaining=("")' not in runner or 'local remaining=()' in runner:
    raise SystemExit("Same-session generated runner is not Bash 3 nounset-safe for empty PID cleanup")
print("Hardened physical runner wrapper self-test passed")'''
if text.count(self_test_print) != 1:
    raise SystemExit("canonical hardened wrapper self-test print is not uniquely patchable")
text = text.replace(self_test_print, self_test_checks)

target.write_text(text, encoding="utf-8")
PY
  chmod 700 "${target}"
}

self_test() {
  python3 -m py_compile "${LAUNCHSERVICES_HARNESS}"
  python3 "${LAUNCHSERVICES_HARNESS}" self-test
  TEMP_WRAPPER="${SCRIPT_DIR}/.run_ci_physical_validation_same_session.selftest.$$.sh"
  materialize_same_session_wrapper "${TEMP_WRAPPER}"
  bash -n "${TEMP_WRAPPER}"
  grep -Fq 'HARNESS="${REPOSITORY}/scripts/run_physical_validation_launchservices.py"' "${TEMP_WRAPPER}"
  grep -Fq 'local remaining=("")' "${TEMP_WRAPPER}"
  bash "${TEMP_WRAPPER}" --self-test
  rm -f -- "${TEMP_WRAPPER}"
  TEMP_WRAPPER=""
  printf '%s\n' 'Same-session physical runner self-test passed'
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit 0
fi

[[ $# -eq 3 ]] || fail "usage: $0 <version> <MacVitals.app> <expected-commit-sha>"
command -v open >/dev/null 2>&1 || fail "LaunchServices open command is unavailable"

TEMP_WRAPPER="${SCRIPT_DIR}/.run_ci_physical_validation_same_session.$$.sh"
materialize_same_session_wrapper "${TEMP_WRAPPER}"
bash -n "${TEMP_WRAPPER}"
grep -Fq 'HARNESS="${REPOSITORY}/scripts/run_physical_validation_launchservices.py"' "${TEMP_WRAPPER}"
grep -Fq 'local remaining=("")' "${TEMP_WRAPPER}"
bash "${TEMP_WRAPPER}" "$@"
