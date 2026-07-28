#!/usr/bin/env python3
"""Collect privacy-safe evidence for unexpected MacVitals process termination."""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import platform
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import NoReturn

MAX_DURATION_SECONDS = 1_800
MAX_OUTPUT_BYTES = 1_048_576
ABSOLUTE_PRIVATE_PATH_RE = re.compile(
    r"/(?:Users|home)/[^/\s]+|/(?:private/)?(?:tmp|var/tmp)/[^\s]+|/(?:private/)?var/folders/[^\s]+"
)


@dataclass(frozen=True)
class ProcessIdentity:
    pid: int
    uid: int
    started_at: str


@dataclass(frozen=True)
class ProcessSample:
    identity: ProcessIdentity
    cpu_percent: float
    rss_kib: int
    vsz_kib: int


def fail(message: str, code: int = 1) -> NoReturn:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def positive_int(value: str) -> int:
    try:
        parsed = int(value, 10)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a positive integer") from error
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return parsed


def positive_float(value: str) -> float:
    try:
        parsed = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a positive number") from error
    if not math.isfinite(parsed) or parsed <= 0:
        raise argparse.ArgumentTypeError("must be a positive number")
    return parsed


def run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        check=False,
        capture_output=True,
        text=True,
        env={**os.environ, "LC_ALL": "C", "LANG": "C"},
    )


def output(*args: str) -> str:
    result = run(*args)
    return result.stdout.strip() if result.returncode == 0 else ""


def parse_ps(raw: str) -> ProcessSample:
    fields = raw.strip().split()
    if len(fields) != 10:
        raise ValueError(f"expected 10 fields, found {len(fields)}")
    identity = ProcessIdentity(
        pid=int(fields[0], 10),
        uid=int(fields[1], 10),
        started_at=" ".join(fields[2:7]),
    )
    cpu = float(fields[7])
    rss = int(fields[8], 10)
    vsz = int(fields[9], 10)
    if not math.isfinite(cpu) or cpu < 0 or rss <= 0 or vsz <= 0:
        raise ValueError("invalid process metrics")
    return ProcessSample(identity, cpu, rss, vsz)


def capture(pid: int) -> ProcessSample | None:
    result = run(
        "ps", "-p", str(pid),
        "-o", "pid=", "-o", "uid=", "-o", "lstart=",
        "-o", "%cpu=", "-o", "rss=", "-o", "vsz=",
    )
    if result.returncode != 0 or not result.stdout.strip():
        return None
    try:
        sample = parse_ps(result.stdout)
    except (ValueError, OverflowError) as error:
        fail(f"Could not parse locale-fixed ps output: {error}")
    if sample.identity.pid != pid:
        fail("ps returned an unexpected PID")
    return sample


def termination_details(return_code: int | None, harness_terminated: bool) -> dict[str, object]:
    if return_code is None:
        return {
            "kind": "running",
            "returnCode": None,
            "signalNumber": None,
            "signalName": None,
            "initiatedByHarness": harness_terminated,
        }
    if return_code < 0:
        number = -return_code
        try:
            name = signal.Signals(number).name
        except ValueError:
            name = "UNKNOWN"
        return {
            "kind": "signal",
            "returnCode": return_code,
            "signalNumber": number,
            "signalName": name,
            "initiatedByHarness": harness_terminated,
        }
    return {
        "kind": "exit",
        "returnCode": return_code,
        "signalNumber": None,
        "signalName": None,
        "initiatedByHarness": harness_terminated,
    }


def sanitize(text: str, replacements: list[str]) -> str:
    result = text.replace("\x00", "<NUL>")
    for value in sorted({item for item in replacements if len(item) >= 3}, key=len, reverse=True):
        result = result.replace(value, "<REDACTED>")
    result = ABSOLUTE_PRIVATE_PATH_RE.sub("<REDACTED_PATH>", result)
    encoded = result.encode("utf-8", errors="replace")
    if len(encoded) > MAX_OUTPUT_BYTES:
        encoded = encoded[:MAX_OUTPUT_BYTES]
        result = encoded.decode("utf-8", errors="ignore") + "\n<TRUNCATED>\n"
    return result


def exact_candidate_running(executable: Path) -> bool:
    candidates = {str(executable), str(executable.absolute()), str(executable.resolve())}
    for raw in output("pgrep", "-x", "MacVitals").splitlines():
        if not raw.strip().isdigit():
            continue
        command = output("ps", "-p", raw.strip(), "-o", "command=")
        if any(command == candidate or command.startswith(candidate + " ") for candidate in candidates):
            return True
    return False


def strict_output_root(path: Path, repository: Path) -> Path:
    resolved = path.resolve()
    try:
        relative = resolved.relative_to(repository.resolve())
    except ValueError as error:
        raise ValueError("output must remain inside the repository") from error
    if relative == Path("."):
        raise ValueError("output must be a strict repository child")
    if path.exists() and (not path.is_dir() or path.is_symlink()):
        raise ValueError("output must be a regular directory")
    path.mkdir(parents=True, exist_ok=True)
    return resolved


def verify_app(app: Path) -> Path:
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        fail("Native Apple Silicon macOS is required")
    if not app.is_dir() or app.is_symlink():
        fail("MacVitals.app must be a regular directory")
    if any(item.is_symlink() for item in app.rglob("*")):
        fail("MacVitals.app must not contain symbolic links")
    executable = app / "Contents" / "MacOS" / "MacVitals"
    if not executable.is_file() or executable.is_symlink() or not os.access(executable, os.X_OK):
        fail("MacVitals executable is missing or unsafe")
    if output("lipo", "-archs", str(executable)) != "arm64":
        fail("MacVitals executable must be exactly arm64")
    return executable.resolve()


def privacy_scan(root: Path, forbidden: list[str]) -> None:
    violations: list[str] = []
    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        data = path.read_bytes()
        if b"\x00" in data:
            violations.append(f"{path.name}:NUL")
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            violations.append(f"{path.name}:non-UTF8")
            continue
        if ABSOLUTE_PRIVATE_PATH_RE.search(text):
            violations.append(f"{path.name}:private-path")
        if any(value and len(value) >= 3 and value in text for value in forbidden):
            violations.append(f"{path.name}:identity")
    if violations:
        fail("Privacy scan failed: " + ", ".join(sorted(set(violations))))
    (root / "PRIVACY_SCAN_PASSED.txt").write_text(
        "Privacy scan passed: no runner identity, workspace, home, or macOS temporary paths.\n",
        encoding="utf-8",
    )


def collect(args: argparse.Namespace) -> int:
    for command in ("lipo", "pgrep", "ps"):
        if shutil.which(command) is None:
            fail(f"Required command is unavailable: {command}", 127)
    repository = args.repository.resolve()
    executable = verify_app(args.app.resolve())
    if args.duration > MAX_DURATION_SECONDS:
        fail(f"Duration must not exceed {MAX_DURATION_SECONDS} seconds", 2)
    output_root = strict_output_root(args.output, repository)
    if exact_candidate_running(executable):
        fail("The exact diagnostic MacVitals candidate is already running")

    sensitive = [
        str(Path.home()),
        str(repository),
        str(args.app.resolve()),
        str(executable),
        os.environ.get("GITHUB_WORKSPACE", ""),
        os.environ.get("RUNNER_NAME", ""),
        os.environ.get("USER", ""),
        socket.gethostname(),
    ]
    started_at = utc_now()
    started = time.monotonic()
    rows: list[dict[str, object]] = []
    harness_terminated = False

    with tempfile.TemporaryFile(mode="w+t", encoding="utf-8", errors="replace") as app_output:
        process = subprocess.Popen(
            [str(executable), "-notificationsEnabled", "NO", "-showInDock", "NO"],
            stdout=app_output,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
            env={**os.environ, "LC_ALL": "C", "LANG": "C"},
        )
        initial: ProcessIdentity | None = None
        deadline = started + args.duration
        next_sample = started
        while time.monotonic() < deadline:
            if process.poll() is not None:
                break
            delay = next_sample - time.monotonic()
            if delay > 0:
                time.sleep(delay)
            if process.poll() is not None:
                break
            sample = capture(process.pid)
            if sample is None:
                process.poll()
                break
            if initial is None:
                initial = sample.identity
            elif sample.identity != initial:
                fail("MacVitals process identity changed during collection")
            rows.append(
                {
                    "timestamp_utc": utc_now(),
                    "elapsed_seconds": time.monotonic() - started,
                    "cpu_percent": sample.cpu_percent,
                    "rss_kib": sample.rss_kib,
                    "vsz_kib": sample.vsz_kib,
                }
            )
            next_sample += args.interval
            if next_sample <= time.monotonic():
                next_sample = time.monotonic() + args.interval

        observed_duration = time.monotonic() - started
        completed = observed_duration + max(3.0, args.interval * 2) >= args.duration
        if process.poll() is None:
            harness_terminated = True
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        return_code = process.returncode
        app_output.flush()
        app_output.seek(0)
        safe_output = sanitize(app_output.read(), sensitive)

    if not rows:
        fail("No MacVitals process samples were collected")

    csv_path = output_root / "samples.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    rss_values = [int(row["rss_kib"]) for row in rows]
    summary = {
        "schemaVersion": 1,
        "startedAt": started_at,
        "finishedAt": utc_now(),
        "requested": {"durationSeconds": args.duration, "intervalSeconds": args.interval},
        "observed": {
            "durationSeconds": observed_duration,
            "sampleCount": len(rows),
            "completedRequestedDuration": completed,
        },
        "process": {
            "pidAtStart": initial.pid if initial else process.pid,
            "uidAtStart": initial.uid if initial else None,
            "startedAt": initial.started_at if initial else None,
            "identityStable": initial is not None,
            "aliveUntilHarnessTermination": completed and harness_terminated,
            "termination": termination_details(return_code, harness_terminated),
        },
        "metrics": {
            "rssKiB": {
                "first": rss_values[0],
                "last": rss_values[-1],
                "growth": rss_values[-1] - rss_values[0],
                "max": max(rss_values),
            },
            "cpuPercentMax": max(float(row["cpu_percent"]) for row in rows),
        },
        "limitations": [
            "This diagnostic records only process lifetime, ps metrics, and sanitized application output.",
            "It performs no SMC writes, fan control, signing, notarization, or privileged-helper registration.",
        ],
    }
    (output_root / "summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (output_root / "app-output.log").write_text(
        safe_output if safe_output else "<no application output>\n", encoding="utf-8"
    )
    privacy_scan(output_root, sensitive)

    termination = summary["process"]["termination"]
    print(
        "MacVitals lifetime diagnostic: "
        f"completed={completed}, samples={len(rows)}, "
        f"termination={termination['kind']}, returnCode={termination['returnCode']}"
    )
    return 0 if completed else 1


def self_test() -> int:
    sample = parse_ps("42 501 Tue Jul 28 12:34:56 2026 1.5 1234 5678")
    assert sample.identity == ProcessIdentity(42, 501, "Tue Jul 28 12:34:56 2026")
    assert sample.cpu_percent == 1.5
    assert termination_details(-15, False)["signalName"] == "SIGTERM"
    assert termination_details(0, False)["kind"] == "exit"
    redacted = sanitize(
        "user /Users/example/private /private/tmp/secret workspace-token",
        ["workspace-token", "example"],
    )
    assert "/Users/" not in redacted
    assert "/private/tmp/" not in redacted
    assert "workspace-token" not in redacted
    print("MacVitals app lifetime diagnostic self-test passed")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path.cwd())
    parser.add_argument("--app", type=Path)
    parser.add_argument("--duration", type=positive_int, default=600)
    parser.add_argument("--interval", type=positive_float, default=2.0)
    parser.add_argument("--output", type=Path, default=Path("app-lifetime-evidence"))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if not args.self_test and args.app is None:
        parser.error("--app is required unless --self-test is used")
    return args


def main() -> int:
    args = parse_args()
    return self_test() if args.self_test else collect(args)


if __name__ == "__main__":
    raise SystemExit(main())
