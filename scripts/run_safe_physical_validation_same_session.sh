#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAFE_WRAPPER="${SCRIPT_DIR}/run_safe_physical_validation.sh"
SAME_SESSION_RUNNER="${SCRIPT_DIR}/run_ci_physical_validation_same_session.sh"
LOCK_HELPER="${SCRIPT_DIR}/physical_runtime_lock.sh"
RECOVERY_GUARD="${SCRIPT_DIR}/physical_preference_recovery_guard.py"
DOMAIN="com.mishkacher.MacVitals"
RECOVERY_ROOT="${HOME}/Library/Caches/MacVitals-CI/physical-validation-recovery"
RESULT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)/physical-validation-results"
TEMP_WRAPPER=""
BEFORE_SESSIONS=""
AFTER_SESSIONS=""

fail() {
  printf 'safe-same-session-physical-validation: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  [[ -z "${TEMP_WRAPPER}" ]] || rm -f -- "${TEMP_WRAPPER}"
  [[ -z "${BEFORE_SESSIONS}" ]] || rm -f -- "${BEFORE_SESSIONS}"
  [[ -z "${AFTER_SESSIONS}" ]] || rm -f -- "${AFTER_SESSIONS}"
}
trap cleanup EXIT HUP INT TERM

for path in "${SAFE_WRAPPER}" "${SAME_SESSION_RUNNER}" "${LOCK_HELPER}" "${RECOVERY_GUARD}"; do
  [[ -f "${path}" && ! -L "${path}" ]] || fail "required validation wrapper is missing or unsafe: ${path}"
done
# shellcheck source=physical_runtime_lock.sh
source "${LOCK_HELPER}"

identify_orphan_recovery_token() {
  local root="$1"
  python3 - "${RECOVERY_GUARD}" "${root}" "${DOMAIN}" <<'PY'
from pathlib import Path
import importlib.util
import re
import sys

helper_path = Path(sys.argv[1])
root_path = Path(sys.argv[2])
domain = sys.argv[3]
spec = importlib.util.spec_from_file_location("macvitals_physical_preference_recovery_guard", helper_path)
if spec is None or spec.loader is None:
    raise SystemExit("preference recovery guard could not be loaded")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)

guard.validate_domain(domain)
root = guard.validate_root(root_path, create=True)
pending = guard.existing_recovery(root)
if not pending:
    raise SystemExit(0)

by_token: dict[str, set[str]] = {}
pattern = re.compile(r"recovery-([A-Za-z0-9._-]+)\.(json|plist)\Z")
for path in pending:
    if path.is_symlink() or not path.is_file():
        raise SystemExit("orphan preference recovery entry is unsafe")
    match = pattern.fullmatch(path.name)
    if match is None:
        raise SystemExit("orphan preference recovery entry has an invalid name")
    token, suffix = match.groups()
    guard.validate_token(token)
    by_token.setdefault(token, set()).add(suffix)

if len(by_token) != 1:
    raise SystemExit("orphan preference recovery is ambiguous")
token, suffixes = next(iter(by_token.items()))
if suffixes != {"json", "plist"}:
    raise SystemExit("orphan preference recovery pair is incomplete")
metadata_path, backup_path = guard.recovery_paths(root, token)
metadata = guard.read_metadata(metadata_path)
if metadata.get("domain") != domain or metadata.get("token") != token:
    raise SystemExit("orphan preference recovery identity mismatch")
guard.ensure_private_regular_file(backup_path, "preference recovery backup")
payload = backup_path.read_bytes()
if metadata.get("backupSha256") != guard.sha256(payload):
    raise SystemExit("orphan preference recovery checksum mismatch")
print(token)
PY
}

recover_orphaned_preferences() {
  local lock_dir sentinel owner_pid token
  lock_dir="$(physical_runtime_lock_directory)"
  if [[ -e "${lock_dir}" || -L "${lock_dir}" ]]; then
    physical_runtime_lock_validate_directory "${lock_dir}" || fail "existing physical runtime lock is unsafe"
    sentinel="${lock_dir}/preferences-recovery-required"
    if [[ -e "${sentinel}" || -L "${sentinel}" ]]; then
      return 0
    fi
    owner_pid="$(physical_runtime_lock_owner_pid "${lock_dir}")"
    [[ "${owner_pid}" =~ ^[0-9]+$ ]] || fail "existing physical runtime lock owner is invalid"
    if physical_runtime_lock_process_is_alive "${owner_pid}"; then
      return 0
    fi
  fi

  token="$(identify_orphan_recovery_token "${RECOVERY_ROOT}")"
  [[ -n "${token}" ]] || return 0
  if pgrep -x MacVitals >/dev/null 2>&1; then
    fail "orphan preference recovery is required but a MacVitals process is running"
  fi
  python3 "${RECOVERY_GUARD}" restore \
    --domain "${DOMAIN}" \
    --token "${token}" \
    --root "${RECOVERY_ROOT}"
  if pgrep -x MacVitals >/dev/null 2>&1; then
    fail "MacVitals appeared during orphan preference recovery"
  fi
  printf 'Recovered validated orphan physical preferences: token=%s\n' "${token}"
}

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

record_sessions() {
  local destination="$1"
  : > "${destination}"
  if [[ ! -e "${RESULT_ROOT}" && ! -L "${RESULT_ROOT}" ]]; then
    return 0
  fi
  [[ -d "${RESULT_ROOT}" && ! -L "${RESULT_ROOT}" ]] || fail "physical validation result root is unsafe"
  if find "${RESULT_ROOT}" -maxdepth 1 -type l -name 'session-*' -print -quit | grep -q .; then
    fail "physical validation result root contains a symbolic-link session"
  fi
  find "${RESULT_ROOT}" -maxdepth 1 -type d -name 'session-*' -print | LC_ALL=C sort > "${destination}"
}

validate_new_session() {
  local before="$1"
  local after="$2"
  local expected_sha="$3"
  python3 - "${before}" "${after}" "${expected_sha}" <<'PY'
from pathlib import Path
import json
import re
import sys

before_path = Path(sys.argv[1])
after_path = Path(sys.argv[2])
expected_sha = sys.argv[3]
if not re.fullmatch(r"[0-9a-f]{40}", expected_sha):
    raise SystemExit("physical acceptance expected SHA is invalid")

def session_set(path: Path) -> set[Path]:
    values: set[Path] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line:
            continue
        candidate = Path(line)
        if candidate.is_symlink() or not candidate.is_dir():
            raise SystemExit("physical acceptance session path is not a regular directory")
        values.add(candidate.resolve())
    return values

new_sessions = sorted(session_set(after_path) - session_set(before_path))
if len(new_sessions) != 1:
    raise SystemExit(f"expected exactly one new physical session, found {len(new_sessions)}")
session = new_sessions[0]

def regular_file(name: str) -> Path:
    path = session / name
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f"physical acceptance file is missing or unsafe: {name}")
    return path

def read_json(name: str) -> dict:
    value = json.loads(regular_file(name).read_text(encoding="utf-8"))
    if not isinstance(value, dict) or value.get("schemaVersion") != 1:
        raise SystemExit(f"physical acceptance JSON is invalid: {name}")
    return value

state = read_json("session.json")
candidate = state.get("candidate")
if not isinstance(candidate, dict) or candidate.get("commit") != expected_sha:
    raise SystemExit("physical acceptance candidate SHA does not match exact validation head")
runs = state.get("runs")
if not isinstance(runs, list) or not runs or not all(isinstance(item, str) and item for item in runs):
    raise SystemExit("physical acceptance session contains no executed runs")

acceptance = read_json("acceptance.json")
scenarios = acceptance.get("scenarios")
if not isinstance(scenarios, dict):
    raise SystemExit("physical acceptance scenarios record is invalid")

def require_pass(name: str) -> None:
    record = scenarios.get(name)
    if not isinstance(record, dict):
        raise SystemExit(f"required physical scenario is missing: {name}")
    if record.get("automatedStatus") != "pass":
        raise SystemExit(f"required physical scenario did not pass: {name}")
    evidence = record.get("evidence")
    if not isinstance(evidence, list) or not evidence or not all(isinstance(item, str) and item for item in evidence):
        raise SystemExit(f"required physical scenario has no evidence: {name}")
    if not any(item in runs for item in evidence):
        raise SystemExit(f"required physical scenario evidence is absent from session runs: {name}")

require_pass("popover-closed")
initial_power = state.get("initialPower")
if not isinstance(initial_power, dict):
    raise SystemExit("physical acceptance initial power record is invalid")
source = str(initial_power.get("source") or "unknown")
if source == "Battery Power":
    require_pass("battery-idle")
elif source == "AC Power" or source.startswith("Adapter"):
    require_pass("external-power-idle")
else:
    raise SystemExit(f"physical acceptance power source is unclassified: {source}")

for name, record in scenarios.items():
    if isinstance(record, dict) and record.get("automatedStatus") == "fail":
        raise SystemExit(f"physical scenario recorded automated failure: {name}")

summary = regular_file("RUNNER_SUMMARY.txt").read_text(encoding="utf-8")
for label in (
    "Automated scenario failures",
    "Required scenario gaps",
    "Instruments gaps",
):
    match = re.search(rf"(?m)^{re.escape(label)}:\s*([0-9]+)\s*$", summary)
    if match is None or int(match.group(1)) != 0:
        raise SystemExit(f"physical runner summary is incomplete: {label}")

privacy = regular_file("PRIVACY_SCAN_PASSED.txt").read_text(encoding="utf-8").strip()
if privacy != "privacy-scan=passed":
    raise SystemExit("physical acceptance privacy scan marker is invalid")

print(f"Same-session physical acceptance evidence passed: {session.name}")
PY
}

self_test() {
  bash "${SAME_SESSION_RUNNER}" --self-test
  TEMP_WRAPPER="${SCRIPT_DIR}/.run_safe_physical_validation_same_session.selftest.$$.sh"
  materialize_wrapper "${TEMP_WRAPPER}"
  bash -n "${TEMP_WRAPPER}"
  bash "${TEMP_WRAPPER}" --self-test

  local fixture_root fixture_session fixture_before fixture_after fixture_sha orphan_root identified rejected
  fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/macvitals-same-session-acceptance.XXXXXX")"
  fixture_session="${fixture_root}/session-self-test"
  fixture_before="${fixture_root}/before.txt"
  fixture_after="${fixture_root}/after.txt"
  fixture_sha="0123456789abcdef0123456789abcdef01234567"
  mkdir -p "${fixture_session}/runs/popover" "${fixture_session}/runs/power"
  : > "${fixture_before}"
  printf '%s\n' "${fixture_session}" > "${fixture_after}"
  python3 - "${fixture_session}" "${fixture_sha}" <<'PY'
from pathlib import Path
import json
import sys

session = Path(sys.argv[1])
sha = sys.argv[2]
(session / "session.json").write_text(json.dumps({
    "schemaVersion": 1,
    "candidate": {"commit": sha},
    "initialPower": {"source": "AC Power"},
    "runs": ["runs/popover", "runs/power"],
}) + "\n", encoding="utf-8")
(session / "acceptance.json").write_text(json.dumps({
    "schemaVersion": 1,
    "scenarios": {
        "popover-closed": {"automatedStatus": "pass", "evidence": ["runs/popover"]},
        "external-power-idle": {"automatedStatus": "pass", "evidence": ["runs/power"]},
        "stability-six-hour": {"automatedStatus": "not-run", "evidence": []},
    },
}) + "\n", encoding="utf-8")
(session / "RUNNER_SUMMARY.txt").write_text(
    "Automated scenario failures: 0\nRequired scenario gaps: 0\nInstruments gaps: 0\n",
    encoding="utf-8",
)
(session / "PRIVACY_SCAN_PASSED.txt").write_text("privacy-scan=passed\n", encoding="utf-8")
PY
  validate_new_session "${fixture_before}" "${fixture_after}" "${fixture_sha}"
  python3 - "${fixture_session}/acceptance.json" <<'PY'
from pathlib import Path
import json
import sys
path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
value["scenarios"]["popover-closed"]["automatedStatus"] = "not-run"
value["scenarios"]["popover-closed"]["evidence"] = []
path.write_text(json.dumps(value) + "\n", encoding="utf-8")
PY
  set +e
  validate_new_session "${fixture_before}" "${fixture_after}" "${fixture_sha}" >/dev/null 2>&1
  rejected=$?
  set -e
  [[ ${rejected} -ne 0 ]] || fail "empty physical acceptance fixture was not rejected"

  orphan_root="$(mktemp -d "${HOME}/.macvitals-orphan-recovery-selftest.XXXXXX")"
  python3 - "${RECOVERY_GUARD}" "${orphan_root}" "${DOMAIN}" <<'PY'
from pathlib import Path
import importlib.util
import json
import plistlib
import sys

helper_path = Path(sys.argv[1])
root = Path(sys.argv[2])
domain = sys.argv[3]
spec = importlib.util.spec_from_file_location("macvitals_physical_preference_recovery_guard_selftest", helper_path)
if spec is None or spec.loader is None:
    raise SystemExit("preference recovery guard self-test import failed")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)
payload = plistlib.dumps({"selfTest": True}, fmt=plistlib.FMT_XML)
token = "orphan-self-test"
metadata_path, backup_path = guard.recovery_paths(root, token)
guard.atomic_write(backup_path, payload, 0o600)
guard.atomic_write(metadata_path, (json.dumps({
    "schemaVersion": 1,
    "domain": domain,
    "token": token,
    "existed": True,
    "backupSha256": guard.sha256(payload),
}, sort_keys=True) + "\n").encode("utf-8"), 0o600)
PY
  identified="$(identify_orphan_recovery_token "${orphan_root}")"
  [[ "${identified}" == "orphan-self-test" ]] || fail "valid orphan preference recovery pair was not identified"
  python3 - "${RECOVERY_GUARD}" "${orphan_root}" "${DOMAIN}" <<'PY'
from pathlib import Path
import importlib.util
import json
import plistlib
import sys
helper_path = Path(sys.argv[1])
root = Path(sys.argv[2])
domain = sys.argv[3]
spec = importlib.util.spec_from_file_location("macvitals_physical_preference_recovery_guard_ambiguous", helper_path)
if spec is None or spec.loader is None:
    raise SystemExit(1)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)
payload = plistlib.dumps({"second": True}, fmt=plistlib.FMT_XML)
token = "second-self-test"
metadata_path, backup_path = guard.recovery_paths(root, token)
guard.atomic_write(backup_path, payload, 0o600)
guard.atomic_write(metadata_path, (json.dumps({
    "schemaVersion": 1,
    "domain": domain,
    "token": token,
    "existed": True,
    "backupSha256": guard.sha256(payload),
}, sort_keys=True) + "\n").encode("utf-8"), 0o600)
PY
  set +e
  identify_orphan_recovery_token "${orphan_root}" >/dev/null 2>&1
  rejected=$?
  set -e
  rm -rf -- "${orphan_root}" "${fixture_root}"
  [[ ${rejected} -ne 0 ]] || fail "ambiguous orphan preference recovery was not rejected"

  rm -f -- "${TEMP_WRAPPER}"
  TEMP_WRAPPER=""
  printf '%s\n' 'Recovery-safe same-session physical wrapper self-test passed'
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit 0
fi

[[ $# -eq 3 ]] || fail "usage: $0 <version> <MacVitals.app> <expected-commit-sha>"
[[ "${3}" =~ ^[0-9a-f]{40}$ ]] || fail "expected commit must be a full lowercase SHA-1"
recover_orphaned_preferences
BEFORE_SESSIONS="$(mktemp "${TMPDIR:-/tmp}/macvitals-sessions-before.XXXXXX")"
AFTER_SESSIONS="$(mktemp "${TMPDIR:-/tmp}/macvitals-sessions-after.XXXXXX")"
record_sessions "${BEFORE_SESSIONS}"

TEMP_WRAPPER="${SCRIPT_DIR}/.run_safe_physical_validation_same_session.$$.sh"
materialize_wrapper "${TEMP_WRAPPER}"
bash -n "${TEMP_WRAPPER}"

set +e
bash "${TEMP_WRAPPER}" "$@"
status=$?
set -e
record_sessions "${AFTER_SESSIONS}"
if [[ ${status} -eq 0 ]]; then
  set +e
  validate_new_session "${BEFORE_SESSIONS}" "${AFTER_SESSIONS}" "${3}"
  validation_status=$?
  set -e
  if [[ ${validation_status} -ne 0 ]]; then
    status=${validation_status}
  fi
fi
exit "${status}"
