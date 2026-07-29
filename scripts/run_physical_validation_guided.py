#!/usr/bin/env python3
"""Guide a physical Apple Silicon validation session without auto-approving evidence."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, NoReturn, Sequence


@dataclass(frozen=True)
class ScenarioProfile:
    name: str
    duration: int
    interval: float
    instruction: str


SCENARIO_PROFILES = (
    ScenarioProfile(
        "battery-idle",
        900,
        2.0,
        "Disconnect external power before starting and keep the Mac on battery.",
    ),
    ScenarioProfile(
        "external-power-idle",
        900,
        2.0,
        "Connect the intended adapter before starting and keep it connected.",
    ),
    ScenarioProfile(
        "adapter-transition",
        300,
        2.0,
        "During the run, disconnect and reconnect power so both states are captured.",
    ),
    ScenarioProfile(
        "sleep-wake",
        300,
        2.0,
        "During the run, put the Mac to sleep long enough to create a visible gap, then wake it.",
    ),
    ScenarioProfile(
        "popover-closed",
        900,
        2.0,
        "Keep the MacVitals popover closed for the entire run.",
    ),
    ScenarioProfile(
        "popover-open",
        900,
        2.0,
        "Keep the MacVitals popover open for the entire run.",
    ),
    ScenarioProfile(
        "high-frequency",
        900,
        0.5,
        "Set the application update interval to 0.5 seconds before starting.",
    ),
    ScenarioProfile(
        "stress",
        900,
        2.0,
        "Run the reviewed CPU/memory stress workload while evidence is collected.",
    ),
    ScenarioProfile(
        "stability-six-hour",
        21_600,
        2.0,
        "Leave the exact candidate running normally for at least six hours.",
    ),
    ScenarioProfile(
        "batteryless-desktop",
        900,
        2.0,
        "Use only on an Apple Silicon desktop with no battery.",
    ),
)
SCENARIO_NAMES = tuple(profile.name for profile in SCENARIO_PROFILES)
REVIEW_STATES = ("pending-review", "pass", "fail", "not-tested", "unsupported")
MANUAL_GATES = (
    "voiceOver",
    "keyboardNavigation",
    "englishVisualReview",
    "russianVisualReview",
    "screenshots",
    "instrumentsTimeProfiler",
    "instrumentsAllocationsLeaks",
    "instrumentsWakeups",
    "instrumentsEnergy",
    "independentReviewer",
    "developerIDSigning",
    "notarizationStapling",
    "cleanMacGatekeeper",
)


class GuideError(RuntimeError):
    """Raised when the guided validation flow cannot proceed safely."""


def fail(message: str, code: int = 1) -> NoReturn:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def run(
    command: Sequence[str],
    *,
    capture: bool = False,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    process_env = {**os.environ, "LC_ALL": "C", "LANG": "C"}
    if env:
        process_env.update(env)
    return subprocess.run(
        list(command),
        check=False,
        text=True,
        capture_output=capture,
        env=process_env,
    )


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise GuideError(f"Could not read valid {path.name}: {error}") from error
    if not isinstance(value, dict):
        raise GuideError(f"{path.name} must contain one JSON object")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def strict_repository_child(path: Path, repository: Path, label: str) -> Path:
    repository = repository.resolve()
    resolved = path.resolve()
    try:
        relative = resolved.relative_to(repository)
    except ValueError as error:
        raise GuideError(f"{label} must remain inside the repository") from error
    if relative == Path("."):
        raise GuideError(f"{label} must be a strict repository child")
    return resolved


def reject_symlink_input(path: Path, label: str) -> None:
    if path.is_symlink():
        raise GuideError(f"{label} must not be a symlink")


def require_commands(*names: str) -> None:
    missing = [name for name in names if shutil.which(name) is None]
    if missing:
        raise GuideError("Required command is unavailable: " + ", ".join(missing))


def ensure_repository(repository: Path) -> Path:
    repository = repository.resolve()
    if not (repository / ".git").exists():
        raise GuideError("Repository does not contain .git")
    if not (repository / "scripts" / "run_physical_validation.py").is_file():
        raise GuideError("Physical validation harness is missing")
    if not (repository / "scripts" / "verify_release.sh").is_file():
        raise GuideError("Release verifier is missing")
    return repository


def profile_for(name: str) -> ScenarioProfile:
    for profile in SCENARIO_PROFILES:
        if profile.name == name:
            return profile
    raise GuideError(f"Unknown physical validation scenario: {name}")


def select(items: Sequence[str], prompt: str) -> str | None:
    for index, item in enumerate(items, start=1):
        print(f"{index}. {item}")
    print("0. Back")
    raw = input(prompt).strip()
    if raw == "0" or not raw:
        return None
    try:
        index = int(raw, 10)
    except ValueError:
        print("Invalid selection.")
        return None
    if not 1 <= index <= len(items):
        print("Invalid selection.")
        return None
    return items[index - 1]


def candidate_identity(dist: Path) -> tuple[str, str, str]:
    manifest = read_json(dist / "BUILD_MANIFEST.json")
    version = manifest.get("version")
    build = manifest.get("buildNumber")
    commit = manifest.get("gitCommit")
    if not all(isinstance(value, str) and value for value in (version, build, commit)):
        raise GuideError("Candidate manifest does not contain version/build/commit")
    if manifest.get("architectures") != ["arm64"]:
        raise GuideError("Candidate manifest architecture must be exactly arm64")
    return str(version), str(build), str(commit)


def expected_candidate_names(version: str) -> set[str]:
    return {
        f"MacVitals-{version}.zip",
        f"MacVitals-{version}.dmg",
        "BUILD_STATUS.txt",
        "BUILD_MANIFEST.json",
        "SHA256SUMS.txt",
    }


def validate_candidate_directory(dist: Path, version: str) -> None:
    entries = list(dist.iterdir())
    found = {entry.name for entry in entries}
    expected = expected_candidate_names(version)
    if found != expected:
        raise GuideError(
            f"Candidate directory scope mismatch; expected {sorted(expected)}, "
            f"found {sorted(found)}"
        )
    unsafe = [
        entry.name
        for entry in entries
        if not entry.is_file() or entry.is_symlink() or entry.stat().st_size == 0
    ]
    if unsafe:
        raise GuideError("Candidate directory contains unsafe entries: " + ", ".join(unsafe))


def verify_before_extraction(repository: Path, dist: Path, version: str) -> None:
    result = run(
        ["bash", str(repository / "scripts" / "verify_release.sh"), version],
        capture=True,
        env={"DIST_DIR": str(dist)},
    )
    if result.returncode != 0:
        raise GuideError(
            "Candidate failed the complete release verifier before extraction; "
            "run verify_release.sh directly to inspect local diagnostics"
        )


def start_session(args: argparse.Namespace) -> tuple[Path, Path]:
    require_commands(
        "bash", "ditto", "lipo", "pmset", "python3", "sw_vers", "sysctl", "uname"
    )
    repository = ensure_repository(args.repository)
    reject_symlink_input(args.dist, "candidate directory")
    reject_symlink_input(args.output_root, "physical validation output")
    reject_symlink_input(args.app_root, "physical validation app root")
    dist = strict_repository_child(args.dist, repository, "candidate directory")
    output_root = strict_repository_child(
        args.output_root, repository, "physical validation output"
    )
    app_root_base = strict_repository_child(
        args.app_root, repository, "physical validation app root"
    )
    if not dist.is_dir():
        raise GuideError("Candidate directory must be a regular repository directory")
    machine = run(["uname", "-m"], capture=True).stdout.strip()
    if machine != "arm64":
        raise GuideError(f"Native arm64 Mac is required; found {machine!r}")

    version, build, commit = candidate_identity(dist)
    validate_candidate_directory(dist, version)
    verify_before_extraction(repository, dist, version)
    candidate_zip = dist / f"MacVitals-{version}.zip"

    app_root_base.mkdir(parents=True, exist_ok=True)
    app_root = app_root_base / f"{version}-{build}-{commit[:12]}"
    if app_root.exists():
        raise GuideError(
            f"Refusing to reuse extracted candidate directory: {app_root.relative_to(repository)}"
        )
    app_root.mkdir()
    extraction = run(["ditto", "-x", "-k", str(candidate_zip), str(app_root)])
    if extraction.returncode != 0:
        shutil.rmtree(app_root, ignore_errors=True)
        raise GuideError("Could not extract the verified candidate ZIP")
    app = app_root / "MacVitals.app"
    if not app.is_dir() or app.is_symlink():
        shutil.rmtree(app_root, ignore_errors=True)
        raise GuideError("Candidate ZIP did not contain a regular MacVitals.app at its root")

    output_root.mkdir(parents=True, exist_ok=True)
    before = {path.resolve() for path in output_root.glob("session-*") if path.is_dir()}
    harness = repository / "scripts" / "run_physical_validation.py"
    result = run(
        [
            sys.executable,
            str(harness),
            "prepare",
            "--repository",
            str(repository),
            "--dist",
            str(dist),
            "--version",
            version,
            "--app",
            str(app),
            "--output-root",
            str(output_root),
        ]
    )
    if result.returncode != 0:
        shutil.rmtree(app_root, ignore_errors=True)
        raise GuideError("Physical validation session preparation failed")
    after = {path.resolve() for path in output_root.glob("session-*") if path.is_dir()}
    created = sorted(after - before)
    if len(created) != 1:
        raise GuideError(f"Expected one new validation session, found {len(created)}")
    session = created[0]
    write_json(
        session / "guided-session.json",
        {
            "schemaVersion": 1,
            "application": str(app.relative_to(repository)),
            "candidateDirectory": str(dist.relative_to(repository)),
            "version": version,
            "build": build,
            "commit": commit,
        },
    )
    print(f"Guided session: {session.relative_to(repository)}")
    print(f"Exact application: {app.relative_to(repository)}")
    return session, app


def load_guided_session(repository: Path, session_path: Path) -> tuple[Path, Path]:
    repository = ensure_repository(repository)
    reject_symlink_input(session_path, "physical validation session")
    session = strict_repository_child(
        session_path, repository, "physical validation session"
    )
    if not session.is_dir():
        raise GuideError("Physical validation session must be a regular directory")
    guide = read_json(session / "guided-session.json")
    application = guide.get("application")
    if not isinstance(application, str) or not application:
        raise GuideError("Guided session application record is invalid")
    app_path = repository / application
    reject_symlink_input(app_path, "test application")
    app = strict_repository_child(app_path, repository, "test application")
    if not app.is_dir():
        raise GuideError("Exact guided test application is missing or unsafe")
    return session, app


def harness_command(repository: Path, *arguments: str) -> int:
    harness = repository / "scripts" / "run_physical_validation.py"
    result = run([sys.executable, str(harness), *arguments])
    return int(result.returncode)


def run_profile(repository: Path, session: Path, app: Path) -> None:
    selected = select(SCENARIO_NAMES, "Scenario: ")
    if selected is None:
        return
    profile = profile_for(selected)
    print()
    print(profile.instruction)
    print(
        f"Duration: {profile.duration} seconds; interval: {profile.interval:g} seconds."
    )
    if input("Type RUN to start: ").strip() != "RUN":
        print("Cancelled.")
        return
    status = harness_command(
        repository,
        "run",
        "--repository",
        str(repository),
        "--session",
        str(session),
        "--scenario",
        profile.name,
        "--app",
        str(app),
        "--duration",
        str(profile.duration),
        "--interval",
        str(profile.interval),
        "--review-status",
        "pending-review",
    )
    if status != 0:
        print("The automated scenario gate failed. Review its evidence before retrying.")
    else:
        print("Automated evidence passed. Record a separate human review decision next.")


def record_scenario_review(repository: Path, session: Path) -> None:
    scenario = select(SCENARIO_NAMES, "Scenario: ")
    if scenario is None:
        return
    state = select(REVIEW_STATES, "Review status: ")
    if state is None:
        return
    note = input("Optional redacted note: ").strip()
    arguments = [
        "review",
        "--session",
        str(session),
        "--scenario",
        scenario,
        "--status",
        state,
    ]
    if note:
        arguments += ["--note", note]
    harness_command(repository, *arguments)


def record_manual_gate(repository: Path, session: Path) -> None:
    gate = select(MANUAL_GATES, "Manual gate: ")
    if gate is None:
        return
    state = select(REVIEW_STATES, "Gate status: ")
    if state is None:
        return
    note = input("Optional redacted note: ").strip()
    arguments = [
        "manual",
        "--session",
        str(session),
        "--gate",
        gate,
        "--status",
        state,
    ]
    if note:
        arguments += ["--note", note]
    harness_command(repository, *arguments)


def show_status(session: Path) -> None:
    state = read_json(session / "session.json")
    acceptance = read_json(session / "acceptance.json")
    print(f"Session status: {state.get('status', 'unknown')}")
    print("Scenarios:")
    scenarios = acceptance.get("scenarios", {})
    for name in SCENARIO_NAMES:
        record = scenarios.get(name, {}) if isinstance(scenarios, dict) else {}
        print(
            f"- {name}: automated={record.get('automatedStatus', 'unknown')}; "
            f"review={record.get('reviewStatus', 'unknown')}"
        )
    print("Manual gates:")
    gates = acceptance.get("manualGates", {})
    for gate in MANUAL_GATES:
        value = gates.get(gate, "unknown") if isinstance(gates, dict) else "unknown"
        print(f"- {gate}: {value}")


def menu(repository: Path, session: Path, app: Path) -> int:
    actions = (
        "Run a physical scenario",
        "Record scenario review",
        "Record manual or Instruments gate",
        "Show current status",
        "Finalize acceptance record",
        "Exit",
    )
    while True:
        print()
        print("MacVitals physical validation")
        print(f"Session: {session.relative_to(repository)}")
        selected = select(actions, "Action: ")
        if selected is None or selected == "Exit":
            return 0
        if selected == "Run a physical scenario":
            run_profile(repository, session, app)
        elif selected == "Record scenario review":
            record_scenario_review(repository, session)
        elif selected == "Record manual or Instruments gate":
            record_manual_gate(repository, session)
        elif selected == "Show current status":
            show_status(session)
        elif selected == "Finalize acceptance record":
            status = harness_command(repository, "finalize", "--session", str(session))
            if status == 0:
                print("All required records are complete.")
            else:
                print(
                    "Acceptance remains incomplete; open items are listed in "
                    "ACCEPTANCE.md."
                )


def start(args: argparse.Namespace) -> int:
    session, app = start_session(args)
    return menu(ensure_repository(args.repository), session, app)


def resume(args: argparse.Namespace) -> int:
    repository = ensure_repository(args.repository)
    session, app = load_guided_session(repository, args.session)
    return menu(repository, session, app)


def self_test(_args: argparse.Namespace | None = None) -> int:
    assert len(SCENARIO_NAMES) == 10
    assert len(set(SCENARIO_NAMES)) == len(SCENARIO_NAMES)
    assert profile_for("high-frequency").duration == 900
    assert profile_for("high-frequency").interval == 0.5
    assert profile_for("stability-six-hour").duration == 21_600
    assert expected_candidate_names("1.2.3") == {
        "MacVitals-1.2.3.zip",
        "MacVitals-1.2.3.dmg",
        "BUILD_STATUS.txt",
        "BUILD_MANIFEST.json",
        "SHA256SUMS.txt",
    }
    assert set(MANUAL_GATES) == {
        "voiceOver",
        "keyboardNavigation",
        "englishVisualReview",
        "russianVisualReview",
        "screenshots",
        "instrumentsTimeProfiler",
        "instrumentsAllocationsLeaks",
        "instrumentsWakeups",
        "instrumentsEnergy",
        "independentReviewer",
        "developerIDSigning",
        "notarizationStapling",
        "cleanMacGatekeeper",
    }
    with tempfile.TemporaryDirectory() as directory:
        repository = Path(directory) / "repo"
        repository.mkdir()
        (repository / ".git").mkdir()
        child = repository / "child"
        assert strict_repository_child(child, repository, "fixture") == child.resolve()
        try:
            strict_repository_child(repository, repository, "fixture")
        except GuideError:
            pass
        else:
            raise AssertionError("Repository root was accepted as an output")
        outside = Path(directory) / "outside"
        try:
            strict_repository_child(outside, repository, "fixture")
        except GuideError:
            pass
        else:
            raise AssertionError("External output was accepted")
        target = repository / "target"
        target.mkdir()
        symlink = repository / "link"
        symlink.symlink_to(target, target_is_directory=True)
        try:
            reject_symlink_input(symlink, "fixture")
        except GuideError:
            pass
        else:
            raise AssertionError("Symlink input was accepted")
    print("Guided physical validation self-test passed")
    return 0


def add_common_paths(parser: argparse.ArgumentParser) -> None:
    root = Path(__file__).resolve().parent.parent
    parser.add_argument("--repository", type=Path, default=root)


def build_parser() -> argparse.ArgumentParser:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    start_parser = commands.add_parser("start")
    add_common_paths(start_parser)
    start_parser.add_argument("--dist", type=Path, default=root / "dist")
    start_parser.add_argument(
        "--output-root", type=Path, default=root / "physical-validation-results"
    )
    start_parser.add_argument(
        "--app-root", type=Path, default=root / "physical-validation-apps"
    )
    start_parser.set_defaults(function=start)

    resume_parser = commands.add_parser("resume")
    add_common_paths(resume_parser)
    resume_parser.add_argument("--session", type=Path, required=True)
    resume_parser.set_defaults(function=resume)

    test_parser = commands.add_parser("self-test")
    test_parser.set_defaults(function=self_test)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        return int(args.function(args))
    except (GuideError, EOFError, KeyboardInterrupt) as error:
        if isinstance(error, KeyboardInterrupt):
            print(file=sys.stderr)
            fail("Cancelled", 130)
        fail(str(error))


if __name__ == "__main__":
    raise SystemExit(main())
