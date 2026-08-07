#!/usr/bin/env python3
"""Conservative hardening overlay for the canonical physical validation harness."""

from __future__ import annotations

import argparse
import json
import math
import re
import tempfile
from pathlib import Path
from typing import Any

import run_physical_validation as base

_ALLOWED_UNSUPPORTED_SCENARIOS = {"batteryless-desktop"}
_DESKTOP_MACHINE_NAMES = ("Mac mini", "Mac Studio", "Mac Pro", "iMac")
_original_parse_power = base.parse_power
_original_power_snapshot = base.power_snapshot
_original_matching_pid = base.matching_pid
_original_terminate = base.terminate
_original_run_scenario = base.run_scenario
_original_review = base.review
_original_manual = base.manual
_original_self_test = base.self_test
_owned_process_executables: dict[int, Path] = {}


def parse_power(raw: str) -> dict[str, Any]:
    """Return an indeterminate battery state when pmset output is incomplete."""
    match = re.search(r"Now drawing from '([^']+)'", raw)
    source = match.group(1).strip() if match else "unknown"
    battery_lines = [line.strip() for line in raw.splitlines() if "%" in line]
    if battery_lines:
        return _original_parse_power(raw)
    return {
        "source": source,
        "batteryPresent": None,
        "percentage": None,
        "state": "unavailable",
        "remaining": None,
    }


def _machine_name_from_system_profiler(raw: str) -> str | None:
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return None
    items = payload.get("SPHardwareDataType") if isinstance(payload, dict) else None
    if not isinstance(items, list) or len(items) != 1 or not isinstance(items[0], dict):
        return None
    value = items[0].get("machine_name")
    return value.strip() if isinstance(value, str) and value.strip() else None


def _explicit_batteryless_desktop(
    *,
    source: str,
    machine_name: str | None,
    battery_registry_output: str,
    registry_status: int,
) -> bool:
    if source != "AC Power" or registry_status != 0:
        return False
    if battery_registry_output.strip():
        return False
    if machine_name is None:
        return False
    return any(
        machine_name == allowed or machine_name.startswith(allowed + " ")
        for allowed in _DESKTOP_MACHINE_NAMES
    )


def power_snapshot(started: float | None = None) -> dict[str, Any]:
    raw = base.output("pmset", "-g", "batt")
    value = parse_power(raw)
    if value.get("batteryPresent") is None:
        hardware = base.command(
            "system_profiler", "SPHardwareDataType", "-detailLevel", "mini", "-json"
        )
        registry = base.command("ioreg", "-r", "-c", "AppleSmartBattery", "-w", "0")
        machine_name = (
            _machine_name_from_system_profiler(hardware.stdout)
            if hardware.returncode == 0
            else None
        )
        if _explicit_batteryless_desktop(
            source=str(value.get("source") or "unknown"),
            machine_name=machine_name,
            battery_registry_output=registry.stdout,
            registry_status=registry.returncode,
        ):
            value["batteryPresent"] = False
    value["recordedAt"] = base.utc_now()
    if started is not None:
        value["elapsedMonotonicSeconds"] = base.time.monotonic() - started
    return value


def _pid_matches_executable(pid: int, executable: Path) -> bool:
    if pid <= 0:
        return False
    current = base.output("ps", "-p", str(pid), "-o", "command=")
    paths = {str(executable), str(executable.absolute()), str(executable.resolve())}
    return any(current == path or current.startswith(path + " ") for path in paths)


def matching_pid(executable: Path, warmup: float) -> tuple[int, bool]:
    pid, owned = _original_matching_pid(executable, warmup)
    if owned:
        _owned_process_executables[pid] = executable.resolve()
    return pid, owned


def terminate(pid: int) -> None:
    executable = _owned_process_executables.pop(pid, None)
    if executable is None:
        return
    if not _pid_matches_executable(pid, executable):
        return
    try:
        base.os.kill(pid, base.signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(20):
        if not _pid_matches_executable(pid, executable):
            return
        base.time.sleep(0.25)
    if not _pid_matches_executable(pid, executable):
        return
    try:
        base.os.kill(pid, base.signal.SIGKILL)
    except ProcessLookupError:
        return


def _finite_number(value: object) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    return number if math.isfinite(number) else None


def _completion_failures(
    scenario_record: dict[str, Any], summary: dict[str, Any] | None
) -> list[str]:
    """Reject interrupted runs that produced a graceful collector summary."""
    failures: list[str] = []
    requested = _finite_number(scenario_record.get("requestedDurationSeconds"))
    interval = _finite_number(scenario_record.get("intervalSeconds"))
    elapsed = _finite_number(scenario_record.get("elapsedSeconds"))
    if requested is None or requested <= 0 or interval is None or interval <= 0:
        return ["scenario duration metadata is invalid"]

    tolerance = max(10.0, interval * 3.0)
    if elapsed is None or elapsed + tolerance < requested:
        failures.append("scenario ended before the requested duration completed")

    if not isinstance(summary, dict):
        failures.append("runtime summary is unavailable for completion validation")
        return failures

    observed = summary.get("observed")
    process = summary.get("process")
    if not isinstance(observed, dict):
        failures.append("runtime observed metadata is invalid")
    else:
        observed_duration = _finite_number(observed.get("durationSeconds"))
        sample_count = observed.get("sampleCount")
        if observed_duration is None or observed_duration + tolerance < requested:
            failures.append("runtime sampling ended before the requested duration completed")
        if isinstance(sample_count, bool) or not isinstance(sample_count, int) or sample_count <= 0:
            failures.append("runtime sample count is invalid")

    if not isinstance(process, dict) or process.get("aliveAtEnd") is not True:
        failures.append("MacVitals was not alive when runtime sampling completed")
    return failures


def run_scenario(args: argparse.Namespace) -> int:
    result = _original_run_scenario(args)
    session = args.session.resolve()
    acceptance_path = session / "acceptance.json"
    acceptance = base.read_json(acceptance_path)
    scenarios = acceptance.get("scenarios")
    record = scenarios.get(args.scenario) if isinstance(scenarios, dict) else None
    if not isinstance(record, dict):
        raise base.ValidationError("Acceptance scenario record is invalid")
    evidence = record.get("evidence")
    if not isinstance(evidence, list) or not evidence or not isinstance(evidence[-1], str):
        return result

    run_dir = session / evidence[-1]
    scenario_path = run_dir / "scenario.json"
    if not scenario_path.is_file() or scenario_path.is_symlink():
        return result
    scenario_record = base.read_json(scenario_path)
    summary: dict[str, Any] | None = None
    summary_relative = scenario_record.get("runtimeSummary")
    if isinstance(summary_relative, str):
        summary_path = session / summary_relative
        if summary_path.is_file() and not summary_path.is_symlink():
            summary = base.read_json(summary_path)

    completion = _completion_failures(scenario_record, summary)
    if not completion:
        return result

    existing = scenario_record.get("failures")
    failures = [item for item in existing if isinstance(item, str)] if isinstance(existing, list) else []
    for failure in completion:
        if failure not in failures:
            failures.append(failure)
    scenario_record["failures"] = failures
    scenario_record["automatedStatus"] = "fail"
    base.write_json(scenario_path, scenario_record)

    record["automatedStatus"] = "fail"
    notes = record.setdefault("notes", [])
    note = "Interrupted or incomplete collection cannot be accepted as an automated pass"
    if isinstance(notes, list) and note not in notes:
        notes.append(note)
    acceptance["lastUpdatedAt"] = base.utc_now()
    base.write_json(acceptance_path, acceptance)
    base.privacy_scan(run_dir)
    for failure in completion:
        print(f"- {failure}", file=base.sys.stderr)
    return 1


def review(args: argparse.Namespace) -> int:
    path = args.session.resolve() / "acceptance.json"
    value = base.read_json(path)
    scenarios = value.get("scenarios")
    if not isinstance(scenarios, dict) or not isinstance(scenarios.get(args.scenario), dict):
        raise base.ValidationError("Acceptance scenario record is invalid")
    record = scenarios[args.scenario]
    automated = record.get("automatedStatus")
    if args.status == "pass" and automated != "pass":
        raise base.ValidationError(
            f"Scenario {args.scenario} cannot pass review before automated evidence passes"
        )
    if args.status == "unsupported" and args.scenario not in _ALLOWED_UNSUPPORTED_SCENARIOS:
        raise base.ValidationError(
            f"Scenario {args.scenario} cannot be marked unsupported"
        )
    return _original_review(args)


def manual(args: argparse.Namespace) -> int:
    if args.status == "unsupported":
        raise base.ValidationError(
            f"Manual gate {args.gate} requires an explicit pass, fail, pending-review, or not-tested state"
        )
    return _original_manual(args)


def _scenario_is_accepted(name: str, record: object) -> bool:
    if not isinstance(record, dict):
        return False
    review_status = record.get("reviewStatus")
    automated_status = record.get("automatedStatus")
    if review_status == "pass":
        return automated_status == "pass"
    return review_status == "unsupported" and name in _ALLOWED_UNSUPPORTED_SCENARIOS


def finalize(args: argparse.Namespace) -> int:
    session = args.session.resolve()
    state = base.read_json(session / "session.json")
    acceptance = base.read_json(session / "acceptance.json")
    scenarios = acceptance.get("scenarios")
    manual_gates = acceptance.get("manualGates")
    if not isinstance(scenarios, dict) or not isinstance(manual_gates, dict):
        raise base.ValidationError("Acceptance record is invalid")

    open_items = [
        f"scenario:{name}"
        for name in base.SCENARIOS
        if not _scenario_is_accepted(name, scenarios.get(name))
    ]
    open_items += [
        f"manual:{name}"
        for name in base.MANUAL_GATES
        if manual_gates.get(name) != "pass"
    ]
    state.update(
        {
            "status": "complete" if not open_items else "incomplete",
            "finalizedAt": base.utc_now(),
            "openItems": open_items,
        }
    )
    base.write_json(session / "session.json", state)

    lines = [
        "# MacVitals Physical Validation Acceptance Record",
        "",
        f"Status: **{state['status']}**",
        "",
        "## Scenarios",
        "",
        "| Scenario | Automated | Review |",
        "|---|---|---|",
    ]
    for name in base.SCENARIOS:
        record = scenarios.get(name, {})
        if not isinstance(record, dict):
            record = {}
        lines.append(
            f"| {name} | {record.get('automatedStatus', 'unknown')} | "
            f"{record.get('reviewStatus', 'unknown')} |"
        )
    lines += ["", "## Manual gates", "", "| Gate | Status |", "|---|---|"]
    lines += [f"| {name} | {manual_gates.get(name, 'unknown')} |" for name in base.MANUAL_GATES]
    lines += ["", "## Open items", ""] + (
        [f"- {item}" for item in open_items] or ["- none"]
    )
    (session / "ACCEPTANCE.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    base.privacy_scan(session)
    print(f"Physical validation session finalized as {state['status']}")
    return 0 if not open_items else 2


def _args(**values: object) -> argparse.Namespace:
    return argparse.Namespace(**values)


def self_test(_args_value: argparse.Namespace | None = None) -> int:
    base.parse_power = _original_parse_power
    base.power_snapshot = _original_power_snapshot
    base.matching_pid = _original_matching_pid
    base.terminate = _original_terminate
    try:
        _original_self_test(None)
    finally:
        base.parse_power = parse_power
        base.power_snapshot = power_snapshot
        base.matching_pid = matching_pid
        base.terminate = terminate

    assert parse_power("")["batteryPresent"] is None
    assert parse_power("pmset failed\n")["batteryPresent"] is None
    assert parse_power("Now drawing from 'unknown'\n")["batteryPresent"] is None
    assert parse_power("Now drawing from 'AC Power'\n")["batteryPresent"] is None
    assert _machine_name_from_system_profiler("not-json") is None
    assert _machine_name_from_system_profiler(
        '{"SPHardwareDataType":[{"machine_name":"Mac Studio"}]}'
    ) == "Mac Studio"
    assert _explicit_batteryless_desktop(
        source="AC Power",
        machine_name="Mac Studio",
        battery_registry_output="",
        registry_status=0,
    )
    assert not _explicit_batteryless_desktop(
        source="AC Power",
        machine_name="MacBook Pro",
        battery_registry_output="",
        registry_status=0,
    )
    assert not _explicit_batteryless_desktop(
        source="AC Power",
        machine_name="Mac Studio",
        battery_registry_output="+-o AppleSmartBattery",
        registry_status=0,
    )
    assert not _explicit_batteryless_desktop(
        source="AC Power",
        machine_name="Mac Studio",
        battery_registry_output="",
        registry_status=1,
    )

    original_output = base.output
    try:
        executable = Path("/tmp/MacVitals.app/Contents/MacOS/MacVitals")
        base.output = lambda *args: str(executable) if args[:2] == ("ps", "-p") else ""
        assert _pid_matches_executable(12345, executable)
        base.output = lambda *args: "/usr/bin/other-process" if args[:2] == ("ps", "-p") else ""
        assert not _pid_matches_executable(12345, executable)
    finally:
        base.output = original_output
    assert base.matching_pid is matching_pid
    assert base.terminate is terminate

    completed = {
        "requestedDurationSeconds": 60,
        "intervalSeconds": 2,
        "elapsedSeconds": 60.1,
    }
    completed_summary = {
        "observed": {"durationSeconds": 60.0, "sampleCount": 31},
        "process": {"aliveAtEnd": True},
    }
    assert not _completion_failures(completed, completed_summary)
    interrupted = {
        "requestedDurationSeconds": 21_600,
        "intervalSeconds": 2,
        "elapsedSeconds": 16_348,
    }
    interrupted_summary = {
        "observed": {"durationSeconds": 16_342, "sampleCount": 8_171},
        "process": {"aliveAtEnd": False},
    }
    interrupted_failures = _completion_failures(interrupted, interrupted_summary)
    assert "scenario ended before the requested duration completed" in interrupted_failures
    assert "MacVitals was not alive when runtime sampling completed" in interrupted_failures

    with tempfile.TemporaryDirectory() as directory:
        session = Path(directory)
        base.write_json(session / "session.json", {"status": "prepared"})
        acceptance = base.acceptance_template()
        base.write_json(session / "acceptance.json", acceptance)

        try:
            review(_args(session=session, scenario="battery-idle", status="pass", note=None))
        except base.ValidationError:
            pass
        else:
            raise AssertionError("Review pass was accepted before automated pass")

        acceptance = base.read_json(session / "acceptance.json")
        acceptance["scenarios"]["battery-idle"]["automatedStatus"] = "pass"
        base.write_json(session / "acceptance.json", acceptance)
        assert review(
            _args(session=session, scenario="battery-idle", status="pass", note=None)
        ) == 0

        try:
            review(
                _args(
                    session=session,
                    scenario="external-power-idle",
                    status="unsupported",
                    note=None,
                )
            )
        except base.ValidationError:
            pass
        else:
            raise AssertionError("Unsupported bypass was accepted for a required scenario")

        try:
            manual(
                _args(
                    session=session,
                    gate="independentReviewer",
                    status="unsupported",
                    note=None,
                )
            )
        except base.ValidationError:
            pass
        else:
            raise AssertionError("Unsupported bypass was accepted for a manual gate")

        acceptance = base.acceptance_template()
        for name in base.SCENARIOS:
            record = acceptance["scenarios"][name]
            if name == "batteryless-desktop":
                record["reviewStatus"] = "unsupported"
            else:
                record["automatedStatus"] = "pass"
                record["reviewStatus"] = "pass"
        for name in base.MANUAL_GATES:
            acceptance["manualGates"][name] = "pass"
        base.write_json(session / "acceptance.json", acceptance)
        assert finalize(_args(session=session)) == 0

        acceptance["scenarios"]["stress"]["automatedStatus"] = "fail"
        base.write_json(session / "acceptance.json", acceptance)
        assert finalize(_args(session=session)) == 2
        state = base.read_json(session / "session.json")
        assert "scenario:stress" in state["openItems"]

    print("Hardened physical validation self-test passed")
    return 0


base.parse_power = parse_power
base.power_snapshot = power_snapshot
base.matching_pid = matching_pid
base.terminate = terminate
base.run_scenario = run_scenario
base.review = review
base.manual = manual
base.finalize = finalize
base.self_test = self_test


if __name__ == "__main__":
    raise SystemExit(base.main())
