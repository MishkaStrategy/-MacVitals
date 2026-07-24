#!/usr/bin/env python3
"""Create redacted, reproducible physical Apple Silicon validation evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, NoReturn

SCENARIOS = (
    "battery-idle", "external-power-idle", "adapter-transition", "sleep-wake",
    "popover-closed", "popover-open", "high-frequency", "stress",
    "stability-six-hour", "batteryless-desktop",
)
STATES = ("pending-review", "pass", "fail", "not-tested", "unsupported")
MANUAL_GATES = (
    "voiceOver", "keyboardNavigation", "englishVisualReview",
    "russianVisualReview", "screenshots", "instrumentsTimeProfiler",
    "instrumentsAllocationsLeaks", "instrumentsWakeups", "instrumentsEnergy",
    "independentReviewer", "developerIDSigning", "notarizationStapling",
    "cleanMacGatekeeper",
)
HOME_RE = re.compile(r"/(?:Users|home)/[^/\s]+")


class ValidationError(RuntimeError):
    pass


def fail(message: str, code: int = 1) -> NoReturn:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def command(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    process_env = {**os.environ, "LC_ALL": "C", "LANG": "C"}
    if env:
        process_env.update(env)
    return subprocess.run(args, capture_output=True, text=True, check=False, env=process_env)


def output(*args: str) -> str:
    result = command(*args)
    return result.stdout.strip() if result.returncode == 0 else ""


def require(*names: str) -> None:
    missing = [name for name in names if shutil.which(name) is None]
    if missing:
        fail("Required command is unavailable: " + ", ".join(missing), 127)


def positive_int(value: str) -> int:
    try:
        result = int(value, 10)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a positive integer") from error
    if result <= 0:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return result


def positive_float(value: str) -> float:
    try:
        result = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a positive number") from error
    if not math.isfinite(result) or result <= 0:
        raise argparse.ArgumentTypeError("must be a positive number")
    return result


def redact(text: str) -> str:
    home = str(Path.home())
    if home:
        text = text.replace(home, "<HOME>")
    return HOME_RE.sub("<HOME>", text)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValidationError(f"Could not read valid {path.name}: {error}") from error
    if not isinstance(value, dict):
        raise ValidationError(f"{path.name} must contain an object")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def strict_child(path: Path, root: Path) -> None:
    try:
        relative = path.resolve().relative_to(root.resolve())
    except ValueError as error:
        raise ValidationError("Validation paths must remain under the repository") from error
    if relative == Path("."):
        raise ValidationError("Validation output must be a strict repository child")


def privacy_scan(root: Path) -> None:
    violations: list[str] = []
    home = str(Path.home())
    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if (home and home in text) or HOME_RE.search(text):
            violations.append(str(path.relative_to(root)))
    if violations:
        raise ValidationError("Evidence contains a home path: " + ", ".join(sorted(violations)))


def parse_power(raw: str) -> dict[str, Any]:
    match = re.search(r"Now drawing from '([^']+)'", raw)
    source = match.group(1).strip() if match else "unknown"
    lines = [line.strip() for line in raw.splitlines() if "%" in line]
    if not lines:
        return {"source": source, "batteryPresent": False, "percentage": None,
                "state": "unavailable", "remaining": None}
    line = lines[0]
    percent_match = re.search(r"\b(\d{1,3})%", line)
    percentage = int(percent_match.group(1)) if percent_match else None
    if percentage is not None and not 0 <= percentage <= 100:
        percentage = None
    lowered = line.lower()
    state = "unknown"
    for candidate in ("finishing charge", "not charging", "discharging",
                      "charging", "charged", "ac attached"):
        if candidate in lowered:
            state = candidate.replace(" ", "-")
            break
    remaining_match = re.search(r"(\d+:\d+) remaining", lowered)
    remaining = remaining_match.group(1) if remaining_match else None
    if "no estimate" in lowered:
        remaining = "unavailable"
    return {"source": source, "batteryPresent": True, "percentage": percentage,
            "state": state, "remaining": remaining}


def power_snapshot(started: float | None = None) -> dict[str, Any]:
    value = parse_power(output("pmset", "-g", "batt"))
    value["recordedAt"] = utc_now()
    if started is not None:
        value["elapsedMonotonicSeconds"] = time.monotonic() - started
    return value


def host_snapshot() -> dict[str, Any]:
    architecture = output("uname", "-m") or "unknown"
    if architecture != "arm64":
        raise ValidationError(f"Native arm64 is required; found {architecture!r}")
    return {
        "architecture": architecture,
        "hardwareModel": output("sysctl", "-n", "hw.model") or "unknown",
        "memoryBytes": output("sysctl", "-n", "hw.memsize") or "unknown",
        "logicalCPUCount": output("sysctl", "-n", "hw.logicalcpu") or "unknown",
        "macOSVersion": output("sw_vers", "-productVersion") or "unknown",
        "macOSBuild": output("sw_vers", "-buildVersion") or "unknown",
    }


def app_identity(app: Path) -> dict[str, Any]:
    info = app / "Contents" / "Info.plist"
    executable = app / "Contents" / "MacOS" / "MacVitals"
    if not info.is_file() or not executable.is_file():
        raise ValidationError("Application bundle is incomplete")
    with info.open("rb") as handle:
        plist = plistlib.load(handle)
    architecture = output("lipo", "-archs", str(executable))
    if architecture != "arm64":
        raise ValidationError(f"Application must be exactly arm64; found {architecture!r}")
    return {
        "bundleIdentifier": plist.get("CFBundleIdentifier"),
        "version": plist.get("CFBundleShortVersionString"),
        "build": plist.get("CFBundleVersion"),
        "executableName": plist.get("CFBundleExecutable"),
        "executableSha256": sha256(executable),
        "architecture": architecture,
    }


def verify_app(app: Path, candidate: dict[str, Any]) -> dict[str, Any]:
    identity = app_identity(app)
    for key in ("bundleIdentifier", "version", "build"):
        expected = candidate.get(key)
        actual = identity.get(key)
        if expected is not None and str(actual) != str(expected):
            raise ValidationError(f"Test app {key} {actual!r} does not match {expected!r}")
    if identity["executableName"] != "MacVitals":
        raise ValidationError("Test application executable is not MacVitals")
    return identity


def candidate_version(dist: Path, requested: str | None) -> str:
    version = read_json(dist / "BUILD_MANIFEST.json").get("version")
    if not isinstance(version, str) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", version):
        raise ValidationError("Candidate manifest version is invalid")
    if requested and requested != version:
        raise ValidationError(f"Requested version {requested} does not match {version}")
    return version


def verify_candidate(root: Path, dist: Path, version: str) -> dict[str, Any]:
    names = (f"MacVitals-{version}.zip", f"MacVitals-{version}.dmg",
             "BUILD_STATUS.txt", "BUILD_MANIFEST.json", "SHA256SUMS.txt")
    for name in names:
        path = dist / name
        if not path.is_file() or path.is_symlink() or path.stat().st_size == 0:
            raise ValidationError(f"Candidate file is missing or unsafe: {name}")
    result = command("bash", str(root / "scripts" / "verify_release.sh"), version,
                     env={"DIST_DIR": str(dist.resolve())})
    if result.returncode:
        raise ValidationError("Release verification failed:\n" + redact(result.stdout + result.stderr))
    manifest = read_json(dist / "BUILD_MANIFEST.json")
    if manifest.get("architectures") != ["arm64"]:
        raise ValidationError("Candidate architecture list must be exactly ['arm64']")
    return {
        "version": version,
        "build": manifest.get("buildNumber"),
        "commit": manifest.get("gitCommit"),
        "bundleIdentifier": manifest.get("bundleIdentifier"),
        "minimumMacOS": manifest.get("minimumMacOS"),
        "architectures": ["arm64"],
        "signingStatus": manifest.get("signingStatus"),
        "notarizationStatus": manifest.get("notarizationStatus"),
        "files": {name: sha256(dist / name) for name in names},
    }


def extracted_identity(dist: Path, version: str) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="macvitals-physical-") as temporary:
        result = command("ditto", "-x", "-k", str(dist / f"MacVitals-{version}.zip"), temporary)
        if result.returncode:
            raise ValidationError("Could not extract verified candidate ZIP")
        return app_identity(Path(temporary) / "MacVitals.app")


def acceptance_template() -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "scenarios": {
            name: {"automatedStatus": "not-run", "reviewStatus": "not-tested",
                   "evidence": [], "notes": []}
            for name in SCENARIOS
        },
        "manualGates": {name: "not-tested" for name in MANUAL_GATES},
        "manualNotes": {},
    }


def prepare(args: argparse.Namespace) -> int:
    require("bash", "ditto", "lipo", "pmset", "python3", "sw_vers", "sysctl", "uname")
    root, dist, output_root, app = (args.repository.resolve(), args.dist.resolve(),
                                    args.output_root.resolve(), args.app.resolve())
    strict_child(dist, root)
    strict_child(output_root, root)
    version = candidate_version(dist, args.version)
    candidate = verify_candidate(root, dist, version)
    test_identity = verify_app(app, candidate)
    if test_identity["executableSha256"] != extracted_identity(dist, version)["executableSha256"]:
        raise ValidationError("Test app executable differs from verified candidate ZIP")
    output_root.mkdir(parents=True, exist_ok=True)
    session = output_root / f"session-{utc_now().replace('-', '').replace(':', '')}-{os.getpid()}"
    session.mkdir(exist_ok=False)
    metadata = session / "candidate-metadata"
    metadata.mkdir()
    for name in ("BUILD_STATUS.txt", "BUILD_MANIFEST.json", "SHA256SUMS.txt"):
        shutil.copy2(dist / name, metadata / name)
    write_json(session / "session.json", {
        "schemaVersion": 1, "status": "prepared", "createdAt": utc_now(),
        "repository": "mishkacher/-MacVitals", "candidate": candidate,
        "host": host_snapshot(), "testApplication": test_identity,
        "testApplicationPath": "<USER_SELECTED_APP>/MacVitals.app",
        "initialPower": power_snapshot(), "runs": [],
    })
    write_json(session / "acceptance.json", acceptance_template())
    (session / "README.txt").write_text(
        "MacVitals physical validation evidence. Review acceptance.json after each run.\n"
        "Never edit runtime CSV/JSON; record decisions through this harness.\n", encoding="utf-8")
    privacy_scan(session)
    print(f"Physical validation session prepared: {session.relative_to(root)}")
    print("Use the run command with this session and the exact tested MacVitals.app.")
    return 0


def matching_pid(executable: Path, warmup: float) -> tuple[int, bool]:
    matches: list[int] = []
    for raw in output("pgrep", "-x", "MacVitals").splitlines():
        if not raw.strip().isdigit():
            continue
        pid = int(raw.strip())
        current = output("ps", "-p", str(pid), "-o", "command=")
        paths = {str(executable), str(executable.absolute()), str(executable.resolve())}
        if any(current == path or current.startswith(path + " ") for path in paths):
            matches.append(pid)
    if len(matches) > 1:
        raise ValidationError("Multiple matching MacVitals processes are running")
    if matches:
        return matches[0], False
    process = subprocess.Popen([str(executable), "-notificationsEnabled", "NO", "-showInDock", "NO"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               start_new_session=True)
    deadline = time.monotonic() + warmup
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise ValidationError("MacVitals exited during validation startup")
        time.sleep(min(0.25, max(0.0, deadline - time.monotonic())))
    return process.pid, True


def terminate(pid: int) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(20):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.25)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def source_kind(item: dict[str, Any]) -> str:
    source = str(item.get("source", "unknown")).lower()
    if "battery" in source:
        return "battery"
    if "ac" in source or "adapter" in source:
        return "external"
    return "unknown"


def initial_requirement(scenario: str, item: dict[str, Any]) -> None:
    kind = source_kind(item)
    if scenario == "battery-idle" and kind != "battery":
        raise ValidationError("battery-idle must start on battery power")
    if scenario == "external-power-idle" and kind != "external":
        raise ValidationError("external-power-idle must start on external power")
    if scenario == "batteryless-desktop" and item.get("batteryPresent") is not False:
        raise ValidationError("batteryless-desktop requires a machine without a battery")


def invariants(scenario: str, interval: float, duration: int,
               timeline: list[dict[str, Any]]) -> list[str]:
    failures: list[str] = []
    kinds = [source_kind(item) for item in timeline]
    if scenario == "battery-idle" and any(kind != "battery" for kind in kinds):
        failures.append("scenario did not remain on battery")
    if scenario == "external-power-idle" and any(kind != "external" for kind in kinds):
        failures.append("scenario did not remain on external power")
    if scenario == "adapter-transition" and not {"battery", "external"} <= set(kinds):
        failures.append("both battery and external power were not captured")
    if scenario == "batteryless-desktop" and any(item.get("batteryPresent") is not False for item in timeline):
        failures.append("a battery was reported")
    if scenario == "high-frequency" and interval > 0.5:
        failures.append("interval must be 0.5 seconds or less")
    if scenario == "stability-six-hour" and duration < 21_600:
        failures.append("duration must be at least 21600 seconds")
    if scenario == "sleep-wake":
        wall = [datetime.fromisoformat(str(item["recordedAt"]).replace("Z", "+00:00")).timestamp()
                for item in timeline]
        gaps = [right - left for left, right in zip(wall, wall[1:])]
        if not gaps or max(gaps) < max(20.0, interval * 4):
            failures.append("no plausible suspended interval was captured")
    return failures


def update_scenario(session: Path, scenario: str, automated: str, review: str,
                    evidence: str, note: str | None) -> None:
    path = session / "acceptance.json"
    value = read_json(path)
    scenarios = value.get("scenarios")
    if not isinstance(scenarios, dict) or not isinstance(scenarios.get(scenario), dict):
        raise ValidationError("Acceptance scenario record is invalid")
    record = scenarios[scenario]
    record["automatedStatus"], record["reviewStatus"] = automated, review
    record.setdefault("evidence", []).append(evidence)
    if note:
        record.setdefault("notes", []).append(redact(note))
    value["lastUpdatedAt"] = utc_now()
    write_json(path, value)


def run_scenario(args: argparse.Namespace) -> int:
    require("lipo", "pgrep", "pmset", "ps", "python3")
    root, session, app = args.repository.resolve(), args.session.resolve(), args.app.resolve()
    state = read_json(session / "session.json")
    candidate = state.get("candidate")
    if not isinstance(candidate, dict):
        raise ValidationError("Session candidate record is invalid")
    verify_app(app, candidate)
    first_power = power_snapshot()
    initial_requirement(args.scenario, first_power)
    started_at, started = utc_now(), time.monotonic()
    run_dir = session / "runs" / f"{args.scenario}-{started_at.replace('-', '').replace(':', '')}-{os.getpid()}"
    run_dir.mkdir(parents=True, exist_ok=False)
    executable = app / "Contents" / "MacOS" / "MacVitals"
    pid, owned = matching_pid(executable, args.warmup)
    collector_root = run_dir / "runtime"
    collector = [sys.executable, str(root / "scripts" / "collect_runtime_metrics.py"),
                 str(args.duration), str(args.interval), "--process-name", "MacVitals",
                 "--process-id", str(pid), "--expected-executable", str(executable),
                 "--output-root", str(collector_root)]
    process = subprocess.Popen(collector, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, env={**os.environ, "LC_ALL": "C", "LANG": "C"})
    timeline: list[dict[str, Any]] = []
    try:
        while process.poll() is None:
            timeline.append(power_snapshot(started))
            time.sleep(min(5.0, max(1.0, args.interval)))
        stdout, stderr = process.communicate(timeout=5)
    finally:
        if owned:
            terminate(pid)
    elapsed = time.monotonic() - started
    (run_dir / "collector.log").write_text(redact((stdout + stderr).strip()) + "\n", encoding="utf-8")
    timeline.append(power_snapshot(started))
    write_json(run_dir / "power-timeline.json", {"samples": timeline})
    summaries = list(collector_root.rglob("summary.json"))
    failures: list[str] = []
    if process.returncode:
        failures.append(f"collector exit code {process.returncode}")
    if len(summaries) != 1:
        failures.append(f"expected one runtime summary, found {len(summaries)}")
    summary_relative: str | None = None
    if len(summaries) == 1:
        summary = read_json(summaries[0])
        summary_relative = str(summaries[0].relative_to(session))
        process_state, observed = summary.get("process"), summary.get("observed")
        if not isinstance(process_state, dict) or process_state.get("identityStable") is not True:
            failures.append("process identity was not stable")
        if not isinstance(observed, dict) or observed.get("clock") != "monotonic":
            failures.append("runtime clock was not monotonic")
    failures.extend(invariants(args.scenario, args.interval, args.duration, timeline))
    automated = "pass" if not failures else "fail"
    write_json(run_dir / "scenario.json", {
        "schemaVersion": 1, "scenario": args.scenario, "startedAt": started_at,
        "finishedAt": utc_now(), "elapsedSeconds": elapsed,
        "requestedDurationSeconds": args.duration, "intervalSeconds": args.interval,
        "powerTimeline": str((run_dir / "power-timeline.json").relative_to(session)),
        "runtimeSummary": summary_relative, "automatedStatus": automated,
        "reviewStatus": args.review_status, "failures": failures,
        "note": redact(args.note) if args.note else None,
    })
    privacy_scan(run_dir)
    relative = str(run_dir.relative_to(session))
    update_scenario(session, args.scenario, automated, args.review_status, relative, args.note)
    state.setdefault("runs", []).append(relative)
    state.update({"status": "in-progress", "lastUpdatedAt": utc_now()})
    write_json(session / "session.json", state)
    print(f"Scenario {args.scenario}: automated {automated}, review {args.review_status}")
    print(f"Evidence: {relative}")
    for failure in failures:
        print(f"- {failure}", file=sys.stderr)
    return 0 if not failures else 1


def review(args: argparse.Namespace) -> int:
    path = args.session.resolve() / "acceptance.json"
    value = read_json(path)
    scenarios = value.get("scenarios")
    if not isinstance(scenarios, dict) or not isinstance(scenarios.get(args.scenario), dict):
        raise ValidationError("Acceptance scenario record is invalid")
    record = scenarios[args.scenario]
    record["reviewStatus"] = args.status
    if args.note:
        record.setdefault("notes", []).append(redact(args.note))
    value["lastUpdatedAt"] = utc_now()
    write_json(path, value)
    privacy_scan(args.session.resolve())
    print(f"Recorded {args.scenario}: {args.status}")
    return 0


def manual(args: argparse.Namespace) -> int:
    path = args.session.resolve() / "acceptance.json"
    value = read_json(path)
    gates = value.get("manualGates")
    if not isinstance(gates, dict) or args.gate not in gates:
        raise ValidationError("Manual gate record is invalid")
    gates[args.gate] = args.status
    if args.note:
        value.setdefault("manualNotes", {}).setdefault(args.gate, []).append(redact(args.note))
    value["lastUpdatedAt"] = utc_now()
    write_json(path, value)
    privacy_scan(args.session.resolve())
    print(f"Recorded manual gate {args.gate}: {args.status}")
    return 0


def finalize(args: argparse.Namespace) -> int:
    session = args.session.resolve()
    state, acceptance = read_json(session / "session.json"), read_json(session / "acceptance.json")
    scenarios, manual_gates = acceptance.get("scenarios", {}), acceptance.get("manualGates", {})
    open_items = [f"scenario:{name}" for name, record in scenarios.items()
                  if isinstance(record, dict) and record.get("reviewStatus") not in {"pass", "unsupported"}]
    open_items += [f"manual:{name}" for name, status in manual_gates.items()
                   if status not in {"pass", "unsupported"}]
    state.update({"status": "complete" if not open_items else "incomplete",
                  "finalizedAt": utc_now(), "openItems": open_items})
    write_json(session / "session.json", state)
    lines = ["# MacVitals Physical Validation Acceptance Record", "",
             f"Status: **{state['status']}**", "", "## Scenarios", "",
             "| Scenario | Automated | Review |", "|---|---|---|"]
    for name in SCENARIOS:
        record = scenarios.get(name, {})
        lines.append(f"| {name} | {record.get('automatedStatus', 'unknown')} | "
                     f"{record.get('reviewStatus', 'unknown')} |")
    lines += ["", "## Manual gates", "", "| Gate | Status |", "|---|---|"]
    lines += [f"| {name} | {manual_gates.get(name, 'unknown')} |" for name in MANUAL_GATES]
    lines += ["", "## Open items", ""] + ([f"- {item}" for item in open_items] or ["- none"])
    (session / "ACCEPTANCE.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    privacy_scan(session)
    print(f"Physical validation session finalized as {state['status']}")
    return 0 if not open_items else 2


def self_test(_args: argparse.Namespace | None = None) -> int:
    battery = parse_power("Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1) 73%; discharging; 4:21 remaining present: true\n")
    assert battery == {"source": "Battery Power", "batteryPresent": True,
                       "percentage": 73, "state": "discharging", "remaining": "4:21"}
    assert parse_power("Now drawing from 'AC Power'\n")["batteryPresent"] is False
    assert redact("/Users/alice/a /home/bob/b") == "<HOME>/a <HOME>/b"
    assert not invariants("adapter-transition", 2, 60,
                          [{"source": "AC Power"}, {"source": "Battery Power"}])
    assert invariants("high-frequency", 2, 60, [{"source": "AC Power"}])
    template = acceptance_template()
    assert set(template["scenarios"]) == set(SCENARIOS)
    assert set(template["manualGates"]) == set(MANUAL_GATES)
    with tempfile.TemporaryDirectory() as temporary:
        path = Path(temporary) / "test.json"
        write_json(path, {"ok": True})
        assert read_json(path) == {"ok": True}
        privacy_scan(Path(temporary))
    print("Physical validation harness self-test passed")
    return 0


def build_parser() -> argparse.ArgumentParser:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare_parser = commands.add_parser("prepare")
    prepare_parser.add_argument("--repository", type=Path, default=root)
    prepare_parser.add_argument("--dist", type=Path, default=root / "dist")
    prepare_parser.add_argument("--version")
    prepare_parser.add_argument("--app", type=Path, required=True)
    prepare_parser.add_argument("--output-root", type=Path,
                                default=root / "physical-validation-results")
    prepare_parser.set_defaults(function=prepare)
    run_parser = commands.add_parser("run")
    run_parser.add_argument("--repository", type=Path, default=root)
    run_parser.add_argument("--session", type=Path, required=True)
    run_parser.add_argument("--scenario", choices=SCENARIOS, required=True)
    run_parser.add_argument("--app", type=Path, required=True)
    run_parser.add_argument("--duration", type=positive_int, default=900)
    run_parser.add_argument("--interval", type=positive_float, default=2.0)
    run_parser.add_argument("--warmup", type=positive_float, default=5.0)
    run_parser.add_argument("--review-status", choices=STATES, default="pending-review")
    run_parser.add_argument("--note")
    run_parser.set_defaults(function=run_scenario)
    review_parser = commands.add_parser("review")
    review_parser.add_argument("--session", type=Path, required=True)
    review_parser.add_argument("--scenario", choices=SCENARIOS, required=True)
    review_parser.add_argument("--status", choices=STATES, required=True)
    review_parser.add_argument("--note")
    review_parser.set_defaults(function=review)
    manual_parser = commands.add_parser("manual")
    manual_parser.add_argument("--session", type=Path, required=True)
    manual_parser.add_argument("--gate", choices=MANUAL_GATES, required=True)
    manual_parser.add_argument("--status", choices=STATES, required=True)
    manual_parser.add_argument("--note")
    manual_parser.set_defaults(function=manual)
    finalize_parser = commands.add_parser("finalize")
    finalize_parser.add_argument("--session", type=Path, required=True)
    finalize_parser.set_defaults(function=finalize)
    test_parser = commands.add_parser("self-test")
    test_parser.set_defaults(function=self_test)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        return int(args.function(args))
    except ValidationError as error:
        fail(str(error))


if __name__ == "__main__":
    raise SystemExit(main())
