#!/usr/bin/env python3
"""Conservative hardening overlay for the canonical physical validation harness."""

from __future__ import annotations

import argparse
import re
import tempfile
from pathlib import Path
from typing import Any

import run_physical_validation as base

_ALLOWED_UNSUPPORTED_SCENARIOS = {"batteryless-desktop"}
_original_parse_power = base.parse_power
_original_review = base.review
_original_manual = base.manual
_original_self_test = base.self_test


def parse_power(raw: str) -> dict[str, Any]:
    """Return an indeterminate battery state when pmset output is not coherent."""
    match = re.search(r"Now drawing from '([^']+)'", raw)
    source = match.group(1).strip() if match else "unknown"
    battery_lines = [line.strip() for line in raw.splitlines() if "%" in line]
    if battery_lines:
        return _original_parse_power(raw)
    if raw.strip() and source == "AC Power":
        return {
            "source": source,
            "batteryPresent": False,
            "percentage": None,
            "state": "unavailable",
            "remaining": None,
        }
    return {
        "source": source,
        "batteryPresent": None,
        "percentage": None,
        "state": "unavailable",
        "remaining": None,
    }


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
    _original_self_test(None)
    assert parse_power("")["batteryPresent"] is None
    assert parse_power("pmset failed\n")["batteryPresent"] is None
    assert parse_power("Now drawing from 'unknown'\n")["batteryPresent"] is None
    assert parse_power("Now drawing from 'AC Power'\n")["batteryPresent"] is False

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
base.review = review
base.manual = manual
base.finalize = finalize
base.self_test = self_test


if __name__ == "__main__":
    raise SystemExit(base.main())
