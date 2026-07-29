#!/bin/bash
# Collect conservative physical Apple Silicon evidence without auto-approving human gates.
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPOSITORY="$(cd "${SCRIPT_DIR}/.." && pwd)"
HARNESS="${REPOSITORY}/scripts/run_physical_validation.py"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

self_test() {
  python3 - "$0" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
for forbidden in (
    "--status " + "pass",
    "--review-status " + "pass",
    "su" + "do ",
    "caffeinate -" + "dims",
    'rm -rf "${local_' + 'trace}"',
):
    if forbidden in text:
        raise SystemExit(f"forbidden physical-runner behavior: {forbidden!r}")
for required in (
    '"popover-' + 'closed" 900 2',
    '"--scenario", "stability-' + 'six-hour"',
    '"--duration", "21600"',
    '"Leaks" ' + '"leaks"',
    '"pending-' + 'review"',
    'MacVitalsPhysical' + 'Evidence',
    'PRIVACY_SCAN_' + 'PASSED.txt',
    'Six-hour stability requires ' + 'external power',
    'launchctl as' + 'user',
    'External power was lost during six-hour stability',
    'MacVitals.app must not contain symbolic links',
    'Local Instruments evidence top-level path must be a regular directory',
):
    if required not in text:
        raise SystemExit(f"required physical-validation contract is missing: {required}")
print("Physical runner script self-test passed")
PY
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit 0
fi

[[ $# -eq 3 ]] || fail "Usage: $0 <version> <MacVitals.app> <expected-commit-sha>"
VERSION="$1"
APP_INPUT="$2"
EXPECTED_SHA="$3"

[[ "${VERSION}" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] || fail "Version must contain one to three numeric components"
[[ "${EXPECTED_SHA}" =~ ^[0-9a-f]{40}$ ]] || fail "Expected commit must be a full lowercase SHA-1"
[[ "$(uname -s)" == "Darwin" ]] || fail "Physical validation requires macOS"
[[ "$(uname -m)" == "arm64" ]] || fail "Physical validation requires native arm64"
[[ -d "${APP_INPUT}" && ! -L "${APP_INPUT}" ]] || fail "MacVitals.app must be a regular non-symlink directory"
APP="$(cd "$(dirname "${APP_INPUT}")" && pwd -P)/$(basename "${APP_INPUT}")"
python3 - "${APP}" "${REPOSITORY}" <<'PYCODE'
from pathlib import Path
import sys

app = Path(sys.argv[1]).resolve()
repository = Path(sys.argv[2]).resolve()
try:
    relative = app.relative_to(repository)
except ValueError as error:
    raise SystemExit("MacVitals.app must remain inside the exact checkout") from error
if relative == Path("."):
    raise SystemExit("MacVitals.app cannot be the repository root")
PYCODE
if find "${APP}" -type l -print -quit | grep -q .; then
  fail "MacVitals.app must not contain symbolic links"
fi
EXECUTABLE="${APP}/Contents/MacOS/MacVitals"
[[ -f "${EXECUTABLE}" && ! -L "${EXECUTABLE}" && -x "${EXECUTABLE}" ]] || fail "MacVitals.app executable must be a regular executable file"
python3 - "${EXECUTABLE}" "${APP}" <<'PYCODE'
from pathlib import Path
import sys

executable = Path(sys.argv[1]).resolve()
application = Path(sys.argv[2]).resolve()
try:
    executable.relative_to(application)
except ValueError as error:
    raise SystemExit("MacVitals executable resolves outside the app bundle") from error
PYCODE
[[ -f "${HARNESS}" && ! -L "${HARNESS}" ]] || fail "Physical validation harness must be a regular non-symlink file"
[[ -n "${HOME:-}" && -d "${HOME}" ]] || fail "Runner HOME is unavailable"
HOME_REAL="$(cd "${HOME}" && pwd -P)"

for command_name in awk bash basename caffeinate comm date ditto env find git grep hostname id launchctl lipo mktemp pmset python3 shasum sort stat sw_vers tr uname wc xcrun; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "Required command is unavailable: ${command_name}"
done

RUNNER_USER="$(id -un)"
RUNNER_UID="$(id -u)"
CONSOLE_USER="$(stat -f '%Su' /dev/console)"
[[ "${CONSOLE_USER}" == "${RUNNER_USER}" ]] || fail "Physical validation requires the active macOS console user"
launchctl print "gui/${RUNNER_UID}" >/dev/null || fail "Physical validation requires an active GUI launchd session"
launchctl asuser "${RUNNER_UID}" /usr/bin/true || fail "Physical validation cannot enter the active GUI bootstrap domain"

gui_exec() {
  launchctl asuser "${RUNNER_UID}" "$@"
}

cd "${REPOSITORY}"
ACTUAL_SHA="$(git rev-parse HEAD)"
[[ "${ACTUAL_SHA}" == "${EXPECTED_SHA}" ]] || fail "Checkout SHA ${ACTUAL_SHA} does not match expected ${EXPECTED_SHA}"
[[ "$(lipo -archs "${EXECUTABLE}")" == "arm64" ]] || fail "Packaged executable is not exactly arm64"

OUTPUT_ROOT="${REPOSITORY}/physical-validation-results"
if [[ -e "${OUTPUT_ROOT}" ]]; then
  [[ -d "${OUTPUT_ROOT}" && ! -L "${OUTPUT_ROOT}" ]] || fail "Physical evidence root must be a regular directory inside the checkout"
else
  mkdir "${OUTPUT_ROOT}"
fi
BEFORE_FILE="$(mktemp)"
AFTER_FILE="$(mktemp)"
TEMP_APP_ROOT=""
cleanup() {
  rm -f "${BEFORE_FILE}" "${AFTER_FILE}"
  if [[ -n "${TEMP_APP_ROOT}" ]]; then
    rm -rf "${TEMP_APP_ROOT}"
  fi
}
trap cleanup EXIT

find "${OUTPUT_ROOT}" -maxdepth 1 -type d -name 'session-*' -print | LC_ALL=C sort > "${BEFORE_FILE}"
python3 "${HARNESS}" prepare \
  --repository "${REPOSITORY}" \
  --dist "${REPOSITORY}/dist" \
  --version "${VERSION}" \
  --app "${APP}" \
  --output-root "${OUTPUT_ROOT}"
find "${OUTPUT_ROOT}" -maxdepth 1 -type d -name 'session-*' -print | LC_ALL=C sort > "${AFTER_FILE}"
SESSION="$(comm -13 "${BEFORE_FILE}" "${AFTER_FILE}")"
[[ -n "${SESSION}" && "$(printf '%s\n' "${SESSION}" | wc -l | tr -d ' ')" == "1" ]] || fail "Expected exactly one new physical validation session"

snapshot() {
  local name="$1"
  {
    printf 'recordedAtUTC=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '%s\n' '--- redacted host and parsed power ---'
    python3 - "${HARNESS}" <<'PYCODE'
from pathlib import Path
import importlib.util
import json
import sys

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("macvitals_physical_harness", path)
if spec is None or spec.loader is None:
    raise SystemExit("Could not load physical validation harness")
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
print(json.dumps({"host": module.host_snapshot(), "power": module.power_snapshot()}, indent=2, sort_keys=True))
PYCODE
    printf '%s\n' '--- pmset thermal ---'
    pmset -g therm || true
  } > "${SESSION}/${name}.txt"
}

power_facts() {
  python3 - "${HARNESS}" <<'PYCODE'
from pathlib import Path
import importlib.util
import sys

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("macvitals_physical_harness", path)
if spec is None or spec.loader is None:
    raise SystemExit("Could not load physical validation harness")
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
power = module.power_snapshot()
source = str(power.get("source") or "unknown")
present = power.get("batteryPresent")
print(source)
print("true" if present is True else "false" if present is False else "unknown")
PYCODE
}

EVIDENCE_RUN_ID="${GITHUB_RUN_ID:-manual-$(date -u '+%Y%m%dT%H%M%SZ')-$$}"
[[ "${EVIDENCE_RUN_ID}" =~ ^[A-Za-z0-9._-]+$ ]] || fail "Local evidence run identifier is unsafe"
LOCAL_EVIDENCE_TOP="${HOME_REAL}/MacVitalsPhysicalEvidence"
LOCAL_EVIDENCE_BASE="${LOCAL_EVIDENCE_TOP}/${EXPECTED_SHA}"
LOCAL_EVIDENCE_ROOT="${LOCAL_EVIDENCE_BASE}/${EVIDENCE_RUN_ID}"
if [[ -e "${LOCAL_EVIDENCE_TOP}" ]]; then
  [[ -d "${LOCAL_EVIDENCE_TOP}" && ! -L "${LOCAL_EVIDENCE_TOP}" ]] || fail "Local Instruments evidence top-level path must be a regular directory"
else
  mkdir "${LOCAL_EVIDENCE_TOP}"
fi
if [[ -e "${LOCAL_EVIDENCE_BASE}" ]]; then
  [[ -d "${LOCAL_EVIDENCE_BASE}" && ! -L "${LOCAL_EVIDENCE_BASE}" ]] || fail "Commit-scoped local Instruments path must be a regular directory"
else
  mkdir "${LOCAL_EVIDENCE_BASE}"
fi
[[ ! -e "${LOCAL_EVIDENCE_ROOT}" ]] || fail "Refusing to overwrite an existing local Instruments evidence run"
mkdir "${LOCAL_EVIDENCE_ROOT}"
chmod 700 "${LOCAL_EVIDENCE_TOP}" "${LOCAL_EVIDENCE_BASE}" "${LOCAL_EVIDENCE_ROOT}" 2>/dev/null || true

SCENARIO_FAILURES=0
REQUIRED_SCENARIO_GAPS=0
INSTRUMENT_GAPS=0
run_scenario() {
  local scenario="$1"
  local duration="$2"
  local interval="$3"
  printf 'Running physical scenario %s for %s seconds at %s-second interval\n' "${scenario}" "${duration}" "${interval}"
  if ! gui_exec caffeinate -ims python3 "${HARNESS}" run \
      --repository "${REPOSITORY}" \
      --session "${SESSION}" \
      --scenario "${scenario}" \
      --app "${APP}" \
      --duration "${duration}" \
      --interval "${interval}" \
      --review-status "pending-review"; then
    printf 'Automated scenario failed: %s\n' "${scenario}" >&2
    SCENARIO_FAILURES=$((SCENARIO_FAILURES + 1))
  fi
}

run_stability_scenario() {
  local poll_seconds="${MACVITALS_POWER_POLL_SECONDS:-30}"
  [[ "${poll_seconds}" =~ ^[0-9]+$ ]] || fail "Power monitor interval must be an integer"
  [[ "${poll_seconds}" -ge 1 && "${poll_seconds}" -le 300 ]] || fail "Power monitor interval must be between 1 and 300 seconds"
  printf 'Running physical scenario stability-six-hour for 21600 seconds with %s-second external-power monitoring\n' "${poll_seconds}"

  set +e
  python3 - \
    "${HARNESS}" \
    "${REPOSITORY}" \
    "${SESSION}" \
    "${APP}" \
    "${RUNNER_UID}" \
    "${poll_seconds}" <<'PYCODE'
from pathlib import Path
import importlib.util
import os
import signal
import subprocess
import sys
import time

harness = Path(sys.argv[1])
repository = Path(sys.argv[2])
session = Path(sys.argv[3])
app = Path(sys.argv[4])
runner_uid = sys.argv[5]
poll_seconds = int(sys.argv[6])

spec = importlib.util.spec_from_file_location("macvitals_physical_harness", harness)
if spec is None or spec.loader is None:
    raise SystemExit("Could not load physical validation harness")
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

command = [
    "launchctl", "asuser", runner_uid,
    "caffeinate", "-ims",
    "python3", str(harness), "run",
    "--repository", str(repository),
    "--session", str(session),
    "--scenario", "stability-six-hour",
    "--app", str(app),
    "--duration", "21600",
    "--interval", "2",
    "--review-status", "pending-review",
]
process = subprocess.Popen(command, start_new_session=True)

def stop_process_group() -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=15)

try:
    while True:
        status = process.poll()
        if status is not None:
            raise SystemExit(status)
        time.sleep(poll_seconds)
        try:
            source = str(module.power_snapshot().get("source") or "unknown")
        except Exception as error:
            print(
                f"External power could not be verified during six-hour stability: {type(error).__name__}",
                file=sys.stderr,
            )
            stop_process_group()
            raise SystemExit(75)
        if source != "AC Power" and not source.startswith("Adapter"):
            print(
                "External power was lost during six-hour stability; stopping to protect the battery",
                file=sys.stderr,
            )
            stop_process_group()
            raise SystemExit(75)
except BaseException:
    if process.poll() is None:
        stop_process_group()
    raise
PYCODE
  local stability_status=$?
  set -e

  if [[ ${stability_status} -eq 0 ]]; then
    return 0
  fi
  if [[ ${stability_status} -eq 75 ]]; then
    python3 "${HARNESS}" review \
      --session "${SESSION}" \
      --scenario "stability-six-hour" \
      --status "not-tested" \
      --note "External power was lost or became unverifiable; collection stopped to protect the battery"
    REQUIRED_SCENARIO_GAPS=$((REQUIRED_SCENARIO_GAPS + 1))
    return 0
  fi
  printf 'Automated scenario failed: stability-six-hour (exit=%s)\n' "${stability_status}" >&2
  SCENARIO_FAILURES=$((SCENARIO_FAILURES + 1))
}

snapshot "runner-before"
run_scenario "popover-closed" 900 2

POWER_FACTS="$(power_facts)"
POWER_SOURCE="$(printf '%s\n' "${POWER_FACTS}" | sed -n '1p')"
BATTERY_PRESENT="$(printf '%s\n' "${POWER_FACTS}" | sed -n '2p')"
case "${POWER_SOURCE}" in
  "Battery Power")
    run_scenario "battery-idle" 900 2
    ;;
  "AC Power"|Adapter*)
    run_scenario "external-power-idle" 900 2
    ;;
  *)
    printf 'Could not classify power source; battery/AC idle scenario remains not-tested\n' >&2
    REQUIRED_SCENARIO_GAPS=$((REQUIRED_SCENARIO_GAPS + 1))
    ;;
esac

if [[ "${BATTERY_PRESENT}" == "false" ]]; then
  run_scenario "batteryless-desktop" 900 2
elif [[ "${BATTERY_PRESENT}" == "true" ]]; then
  python3 "${HARNESS}" review \
    --session "${SESSION}" \
    --scenario "batteryless-desktop" \
    --status "unsupported" \
    --note "Battery is present; a separate Apple Silicon desktop is required"
else
  printf 'Battery presence could not be determined; optional desktop scenario remains not-tested\n' >&2
fi

STABILITY_FACTS="$(power_facts)"
STABILITY_SOURCE="$(printf '%s\n' "${STABILITY_FACTS}" | sed -n '1p')"
if [[ "${STABILITY_SOURCE}" == "AC Power" || "${STABILITY_SOURCE}" == Adapter* ]]; then
  run_stability_scenario
else
  python3 "${HARNESS}" review \
    --session "${SESSION}" \
    --scenario "stability-six-hour" \
    --status "not-tested" \
    --note "Six-hour stability requires external power; skipped to prevent battery depletion"
  printf 'Six-hour stability requires external power; current source is %s\n' "${STABILITY_SOURCE}" >&2
  REQUIRED_SCENARIO_GAPS=$((REQUIRED_SCENARIO_GAPS + 1))
fi
snapshot "runner-after-stability"

INSTRUMENTS_SESSION="${SESSION}/instruments"
mkdir -p "${INSTRUMENTS_SESSION}"
printf '%s\n' "<HOME>/MacVitalsPhysicalEvidence/<exact-commit-sha>/${EVIDENCE_RUN_ID}/" > "${INSTRUMENTS_SESSION}/LOCAL_EVIDENCE_POINTER.txt"

TEMP_APP_ROOT="$(mktemp -d /private/tmp/macvitals-instruments.XXXXXX)"
TRACE_APP="${TEMP_APP_ROOT}/MacVitals.app"
ditto "${APP}" "${TRACE_APP}"
TRACE_EXECUTABLE="${TRACE_APP}/Contents/MacOS/MacVitals"
TRACE_HOME="${TEMP_APP_ROOT}/home"
mkdir -p "${TRACE_HOME}"

sanitize_text() {
  local source="$1"
  local target="$2"
  local user_name
  local host_name
  user_name="$(id -un 2>/dev/null || true)"
  host_name="$(hostname 2>/dev/null || true)"
  REDACT_HOME="${HOME_REAL}" REDACT_USER="${user_name}" REDACT_HOST="${host_name}" REDACT_TEMP="${TEMP_APP_ROOT}" \
    python3 - "${source}" "${target}" <<'PYCODE'
from pathlib import Path
import os
import re
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
text = source.read_text(encoding="utf-8", errors="strict")
text = re.sub(r"/(?:Users|home)/[^/\s<]+", "<HOME>", text)
text = re.sub(r"\bInternalBattery-\d+(?:\s+\(id=\d+\))?", "<BATTERY_ID>", text)
for value, replacement in (
    (os.environ.get("REDACT_HOME", ""), "<HOME>"),
    (os.environ.get("REDACT_TEMP", ""), "<TRACE_WORKSPACE>"),
    (os.environ.get("REDACT_USER", ""), "<USER>"),
    (os.environ.get("REDACT_HOST", ""), "<HOST>"),
):
    if value:
        text = text.replace(value, replacement)
target.write_text(text, encoding="utf-8")
PYCODE
}

TEMPLATES_FILE="${INSTRUMENTS_SESSION}/available-templates.txt"
gui_exec env HOME="${TRACE_HOME}" LC_ALL=C LANG=C xcrun xctrace list templates > "${TEMP_APP_ROOT}/templates.raw.txt" 2>&1 || true
sanitize_text "${TEMP_APP_ROOT}/templates.raw.txt" "${TEMPLATES_FILE}"
printf 'template\tslug\tstatus\tarchiveSha256\tlocalArchive\n' > "${INSTRUMENTS_SESSION}/status.tsv"

record_instrument() {
  local template="$1"
  local slug="$2"
  local duration="$3"
  local raw_trace="${TEMP_APP_ROOT}/${slug}.trace"
  local raw_log="${TEMP_APP_ROOT}/${slug}.raw.log"
  local safe_log="${INSTRUMENTS_SESSION}/${slug}.log"
  local toc_raw="${TEMP_APP_ROOT}/${slug}-toc.raw.xml"
  local toc_safe="${INSTRUMENTS_SESSION}/${slug}-toc.xml"
  local archive="${LOCAL_EVIDENCE_ROOT}/${slug}.trace.zip"
  local archive_sha=""

  if ! grep -Fq "${template}" "${TEMP_APP_ROOT}/templates.raw.txt"; then
    printf '%s\t%s\tunavailable\t\t\n' "${template}" "${slug}" >> "${INSTRUMENTS_SESSION}/status.tsv"
    return 0
  fi

  set +e
  gui_exec env HOME="${TRACE_HOME}" LC_ALL=C LANG=C xcrun xctrace record \
    --no-prompt \
    --template "${template}" \
    --time-limit "${duration}s" \
    --output "${raw_trace}" \
    --launch -- "${TRACE_EXECUTABLE}" -notificationsEnabled NO -showInDock NO \
    > "${raw_log}" 2>&1
  local trace_status=$?
  set -e
  sanitize_text "${raw_log}" "${safe_log}"

  if [[ ${trace_status} -ne 0 || ! -e "${raw_trace}" ]]; then
    printf '%s\t%s\tfailed(exit=%s)\t\t\n' "${template}" "${slug}" "${trace_status}" >> "${INSTRUMENTS_SESSION}/status.tsv"
    return 0
  fi

  [[ ! -e "${archive}" ]] || fail "Refusing to overwrite an existing local Instruments archive"
  ditto -c -k --keepParent "${raw_trace}" "${archive}"
  archive_sha="$(shasum -a 256 "${archive}" | awk '{print $1}')"

  set +e
  gui_exec env HOME="${TRACE_HOME}" LC_ALL=C LANG=C xcrun xctrace export --input "${raw_trace}" --toc --output "${toc_raw}" >> "${raw_log}" 2>&1
  local export_status=$?
  set -e
  sanitize_text "${raw_log}" "${safe_log}"
  if [[ ${export_status} -eq 0 && -f "${toc_raw}" ]]; then
    sanitize_text "${toc_raw}" "${toc_safe}"
  fi

  printf '%s\t%s\tcollected-pending-review\t%s\t<HOME>/MacVitalsPhysicalEvidence/%s/%s.trace.zip\n' \
    "${template}" "${slug}" "${archive_sha}" "${EXPECTED_SHA}/${EVIDENCE_RUN_ID}" "${slug}" >> "${INSTRUMENTS_SESSION}/status.tsv"
}

instrument_status() {
  local slug="$1"
  awk -F '\t' -v wanted="${slug}" 'NR > 1 && $2 == wanted { print $3; exit }' "${INSTRUMENTS_SESSION}/status.tsv"
}

mark_instrument_gate() {
  local gate="$1"
  local description="$2"
  shift 2
  local all_collected=1
  local details=""
  local slug
  local status
  for slug in "$@"; do
    status="$(instrument_status "${slug}")"
    [[ -n "${status}" ]] || status="missing"
    details+="${slug}=${status}; "
    if [[ "${status}" != "collected-pending-review" ]]; then
      all_collected=0
    fi
  done
  if [[ ${all_collected} -eq 1 ]]; then
    python3 "${HARNESS}" manual \
      --session "${SESSION}" \
      --gate "${gate}" \
      --status "pending-review" \
      --note "${description} collected locally with SHA-256; human review required"
  else
    python3 "${HARNESS}" manual \
      --session "${SESSION}" \
      --gate "${gate}" \
      --status "not-tested" \
      --note "${description} incomplete: ${details}"
    INSTRUMENT_GAPS=$((INSTRUMENT_GAPS + 1))
  fi
}

record_instrument "Time Profiler" "time-profiler" 300
record_instrument "Allocations" "allocations" 300
record_instrument "Leaks" "leaks" 300
record_instrument "System Trace" "system-trace" 180
record_instrument "Energy Log" "energy-log" 300

mark_instrument_gate "instrumentsTimeProfiler" "Time Profiler trace" "time-profiler"
mark_instrument_gate "instrumentsAllocationsLeaks" "Allocations and Leaks traces" "allocations" "leaks"
mark_instrument_gate "instrumentsWakeups" "System Trace wakeups evidence" "system-trace"
mark_instrument_gate "instrumentsEnergy" "Energy Log trace" "energy-log"

python3 - "${INSTRUMENTS_SESSION}/status.tsv" "${INSTRUMENTS_SESSION}/status.json" <<'PY'
from pathlib import Path
import csv
import json
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
with source.open(encoding="utf-8", newline="") as handle:
    rows = list(csv.DictReader(handle, delimiter="\t"))
target.write_text(json.dumps({"schemaVersion": 1, "traces": rows}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

snapshot "runner-final"
printf 'Exact commit: %s\nVersion: %s\nSession: %s\nLocal Instruments run: %s\nAutomated scenario failures: %s\nRequired scenario gaps: %s\nInstruments gaps: %s\n' \
  "${EXPECTED_SHA}" "${VERSION}" "$(basename "${SESSION}")" "${EVIDENCE_RUN_ID}" \
  "${SCENARIO_FAILURES}" "${REQUIRED_SCENARIO_GAPS}" "${INSTRUMENT_GAPS}" \
  > "${SESSION}/RUNNER_SUMMARY.txt"

set +e
python3 "${HARNESS}" finalize --session "${SESSION}"
FINALIZE_STATUS=$?
set -e

REDACT_HOME="${HOME_REAL}" REDACT_USER="$(id -un 2>/dev/null || true)" REDACT_HOST="$(hostname 2>/dev/null || true)" REDACT_TEMP="${TEMP_APP_ROOT}" \
  python3 - "${SESSION}" <<'PYCODE'
from pathlib import Path
import os
import re
import sys

root = Path(sys.argv[1])
if root.is_symlink() or not root.is_dir():
    raise SystemExit("Physical session is not a regular directory")

home = os.environ.get("REDACT_HOME", "")
user = os.environ.get("REDACT_USER", "")
host = os.environ.get("REDACT_HOST", "")
temp = os.environ.get("REDACT_TEMP", "")
replacements = [(home, "<HOME>"), (temp, "<TRACE_WORKSPACE>"), (host, "<HOST>")]
if len(user) >= 3:
    replacements.append((user, "<USER>"))
path_pattern = re.compile(r"/(?:Users|home)/[^/\s<]+")
temp_pattern = re.compile(r"/private/tmp/macvitals-instruments\.[^/\s<]+")
battery_pattern = re.compile(r"\bInternalBattery-\d+(?:\s+\(id=\d+\))?")

def sanitize(text: str) -> str:
    text = path_pattern.sub("<HOME>", text)
    text = temp_pattern.sub("<TRACE_WORKSPACE>", text)
    text = battery_pattern.sub("<BATTERY_ID>", text)
    for value, replacement in replacements:
        if value:
            text = text.replace(value, replacement)
    return text

for path in sorted(root.rglob("*")):
    if path.is_symlink():
        raise SystemExit(f"Symlink is forbidden in physical session: {path.name}")
    if path.is_dir():
        continue
    if not path.is_file():
        raise SystemExit(f"Non-regular physical session entry: {path.name}")
    if path.stat().st_nlink != 1:
        raise SystemExit(f"Hard-linked physical session entry is forbidden: {path.name}")
    payload = path.read_bytes()
    if b"\x00" in payload:
        raise SystemExit(f"Binary data is forbidden in uploadable physical session: {path.name}")
    clean = sanitize(payload.decode("utf-8", errors="strict"))
    for value, _ in replacements:
        if value and value in clean:
            raise SystemExit(f"Privacy scan failed for {path.name}")
    if path_pattern.search(clean) or temp_pattern.search(clean) or "InternalBattery-" in clean:
        raise SystemExit(f"Privacy pattern remained in {path.name}")
    path.write_text(clean, encoding="utf-8")

(root / "PRIVACY_SCAN_PASSED.txt").write_text("privacy-scan=passed\n", encoding="utf-8")
PYCODE

if [[ ${FINALIZE_STATUS} -ne 0 && ${FINALIZE_STATUS} -ne 2 ]]; then
  fail "Physical validation finalize failed with exit ${FINALIZE_STATUS}"
fi
if [[ ${SCENARIO_FAILURES} -ne 0 ]]; then
  fail "${SCENARIO_FAILURES} automated physical scenario(s) failed; sanitized evidence was retained"
fi
if [[ ${REQUIRED_SCENARIO_GAPS} -ne 0 ]]; then
  fail "${REQUIRED_SCENARIO_GAPS} required physical scenario(s) remain uncollected; sanitized evidence was retained"
fi
if [[ ${INSTRUMENT_GAPS} -ne 0 ]]; then
  fail "${INSTRUMENT_GAPS} required Instruments gate(s) remain uncollected; sanitized evidence was retained"
fi

printf 'Physical runner collection completed; human and independent gates remain open.\n'
