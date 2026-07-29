#!/usr/bin/env python3
"""Collect MacVitals runtime evidence with monotonic time and stable identity."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import platform
import shutil
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import NoReturn


@dataclass(frozen=True)
class Identity:
    pid: int
    uid: int
    started_at: str
    command: str

    @property
    def executable_name(self) -> str:
        return Path(self.command).name

    @property
    def token(self) -> str:
        raw = f"{self.uid}\0{self.started_at}\0{self.command}".encode()
        return hashlib.sha256(raw).hexdigest()


@dataclass(frozen=True)
class Sample:
    identity: Identity
    cpu: float
    rss: float
    vsz: float
    threads: int | None = None


def fail(message: str, code: int = 1) -> NoReturn:
    print(message, file=sys.stderr)
    raise SystemExit(code)


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


def finite_nonnegative(value: str, field: str) -> float:
    try:
        parsed = float(value)
    except ValueError as error:
        raise ValueError(f"Invalid {field}: {value!r}") from error
    if not math.isfinite(parsed) or parsed < 0:
        raise ValueError(f"Invalid {field}: {value!r}")
    return parsed


def integer_field(value: str, field: str, *, allow_zero: bool = False) -> int:
    try:
        parsed = int(value, 10)
    except ValueError as error:
        raise ValueError(f"Invalid {field}: {value!r}") from error
    minimum = 0 if allow_zero else 1
    if parsed < minimum:
        raise ValueError(f"Invalid {field}: {value!r}")
    return parsed


def run(*args: str) -> subprocess.CompletedProcess[str]:
    environment = dict(os.environ)
    environment.update(LC_ALL="C", LANG="C")
    return subprocess.run(
        args,
        check=False,
        capture_output=True,
        text=True,
        env=environment,
    )


def output(*args: str) -> str:
    result = run(*args)
    return result.stdout.strip() if result.returncode == 0 else ""


def parse_pids(raw: str) -> list[int]:
    return sorted(
        {
            integer_field(line.strip(), "PID")
            for line in raw.splitlines()
            if line.strip()
        }
    )


def resolve_pid(name: str, explicit: int | None) -> tuple[int, str]:
    if explicit is not None:
        return explicit, "explicit-pid"
    result = run("pgrep", "-x", name)
    if result.returncode not in (0, 1):
        fail(f"Could not query exact process name {name!r}")
    candidates = parse_pids(result.stdout)
    if not candidates:
        fail(f"{name} is not running. Launch the packaged app first.")
    if len(candidates) != 1:
        joined = ", ".join(map(str, candidates))
        fail(
            f"Multiple exact {name} processes are running ({joined}). "
            "Set PROCESS_ID explicitly."
        )
    return candidates[0], "exact-name-single-match"


def parse_ps(raw: str) -> Sample:
    lines = [line.strip() for line in raw.splitlines() if line.strip()]
    if len(lines) != 1:
        raise ValueError(f"Expected one ps row, found {len(lines)}")
    fields = lines[0].split()
    # LC_ALL=C lstart is: weekday month day HH:MM:SS year.
    if len(fields) < 11:
        raise ValueError(f"Incomplete ps row: {lines[0]!r}")
    command = " ".join(fields[10:]).strip()
    if not command:
        raise ValueError("Empty ps command")
    return Sample(
        identity=Identity(
            pid=integer_field(fields[0], "PID"),
            uid=integer_field(fields[1], "UID", allow_zero=True),
            started_at=" ".join(fields[2:7]),
            command=command,
        ),
        cpu=finite_nonnegative(fields[7], "CPU"),
        rss=finite_nonnegative(fields[8], "RSS"),
        vsz=finite_nonnegative(fields[9], "VSZ"),
    )


def thread_mode(pid: int) -> str:
    count = output("ps", "-p", str(pid), "-o", "thcount=")
    if count.isdigit() and int(count, 10) > 0:
        return "thcount"
    return "thread-list" if run("ps", "-M", "-p", str(pid)).returncode == 0 else "unavailable"


def thread_count(pid: int, mode: str) -> int | None:
    if mode == "thcount":
        value = output("ps", "-p", str(pid), "-o", "thcount=")
        return int(value, 10) if value.isdigit() and int(value, 10) > 0 else None
    if mode == "thread-list":
        result = run("ps", "-M", "-p", str(pid))
        lines = [line for line in result.stdout.splitlines() if line.strip()]
        count = len(lines) - 1 if result.returncode == 0 else 0
        return count if count > 0 else None
    return None


def capture(pid: int, mode: str) -> Sample | None:
    result = run(
        "ps", "-p", str(pid),
        "-o", "pid=", "-o", "uid=", "-o", "lstart=",
        "-o", "%cpu=", "-o", "rss=", "-o", "vsz=", "-o", "comm=",
    )
    if result.returncode != 0 or not result.stdout.strip():
        return None
    try:
        sample = parse_ps(result.stdout)
    except ValueError as error:
        fail(f"Could not parse locale-fixed ps output: {error}")
    if sample.identity.pid != pid:
        fail(f"ps returned PID {sample.identity.pid}, expected {pid}")
    return Sample(sample.identity, sample.cpu, sample.rss, sample.vsz, thread_count(pid, mode))


def validate_executable(pid: int, expected: Path | None) -> None:
    if expected is None:
        return
    command_line = output("ps", "-p", str(pid), "-o", "command=")
    if not command_line:
        fail(f"Could not read command line for PID {pid}")
    candidates = {str(expected), str(expected.absolute()), str(expected.resolve())}
    if not any(
        command_line == candidate or command_line.startswith(candidate + " ")
        for candidate in candidates
    ):
        fail(f"PID {pid} is not the expected executable")


def percentile(values: list[float], probability: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = math.ceil(probability * len(ordered)) - 1
    return ordered[max(0, min(len(ordered) - 1, index))]


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def environment_value(*args: str) -> str:
    return output(*args) or "unknown"


def summary(
    args: argparse.Namespace,
    identity: Identity,
    selection: str,
    mode: str,
    rows: list[dict[str, float | int | str | None]],
    duration: float,
    alive: bool,
) -> dict[str, object]:
    elapsed = [float(row["elapsed_seconds"]) for row in rows]
    cpu = [float(row["cpu_percent"]) for row in rows]
    rss = [float(row["rss_kib"]) for row in rows]
    vsz = [float(row["vsz_kib"]) for row in rows]
    threads = [float(row["threads"]) for row in rows if row["threads"] is not None]
    intervals = [b - a for a, b in zip(elapsed, elapsed[1:])]
    if any(value < 0 for value in intervals):
        fail("Elapsed sample times are not monotonic")
    metric = lambda values: {
        "mean": statistics.fmean(values),
        "p95": percentile(values, 0.95),
        "max": max(values),
    }
    return {
        "schemaVersion": 3,
        "process": {
            "name": args.process_name,
            "pidAtStart": identity.pid,
            "uidAtStart": identity.uid,
            "startedAt": identity.started_at,
            "executableName": identity.executable_name,
            "identityTokenSha256": identity.token,
            "identityStable": True,
            "aliveAtEnd": alive,
            "selectionMode": selection,
            "expectedExecutableName": args.expected_executable.name
            if args.expected_executable else None,
        },
        "requested": {
            "durationSeconds": args.duration_seconds,
            "intervalSeconds": args.interval_seconds,
        },
        "observed": {
            "clock": "monotonic",
            "sampleSource": "locale-fixed-single-ps-snapshot",
            "durationSeconds": duration,
            "firstSampleElapsedSeconds": elapsed[0],
            "lastSampleElapsedSeconds": elapsed[-1],
            "sampleCount": len(rows),
            "sampleIntervalSeconds": {
                "mean": statistics.fmean(intervals) if intervals else None,
                "p95": percentile(intervals, 0.95),
                "max": max(intervals) if intervals else None,
            },
        },
        "environment": {
            "architecture": platform.machine(),
            "macOSVersion": environment_value("sw_vers", "-productVersion"),
            "macOSBuild": environment_value("sw_vers", "-buildVersion"),
            "hardwareModel": environment_value("sysctl", "-n", "hw.model"),
            "logicalCPUCount": environment_value("sysctl", "-n", "hw.logicalcpu"),
            "physicalMemoryBytes": environment_value("sysctl", "-n", "hw.memsize"),
            "threadCountSource": mode,
            "processLocale": "C",
        },
        "metrics": {
            "cpuPercent": metric(cpu),
            "residentMemoryKiB": {
                **metric(rss), "first": rss[0], "last": rss[-1],
                "growth": rss[-1] - rss[0], "range": max(rss) - min(rss),
            },
            "virtualMemoryKiB": {
                **metric(vsz), "first": vsz[0], "last": vsz[-1],
                "growth": vsz[-1] - vsz[0],
            },
            "threads": metric(threads) if threads else {"mean": None, "p95": None, "max": None},
        },
        "limitations": [
            "This is process sampling from ps, not an Instruments energy or wakeup trace.",
            "Values are evidence for the recorded machine and workload only.",
            "CI thresholds are broad regression guardrails, not product performance claims.",
            "Process identity is pinned by PID, UID, start time and executable identity.",
            "No administrator privileges, network access, serial numbers, "
            "usernames, home paths, or user documents are recorded.",
        ],
    }


def collect(args: argparse.Namespace) -> Path:
    for command in ("pgrep", "ps"):
        if shutil.which(command) is None:
            fail(f"Required command is unavailable: {command}", 127)
    pid, selection = resolve_pid(args.process_name, args.process_id)
    validate_executable(pid, args.expected_executable)
    mode = thread_mode(pid)
    first = capture(pid, mode)
    if first is None:
        fail(f"{args.process_name} exited before collection started")
    identity = first.identity
    if identity.executable_name != args.process_name:
        fail(f"PID {pid} executable is {identity.executable_name!r}")

    run_id = f"{utc_now().replace('-', '').replace(':', '')}-{os.getpid()}"
    directory = args.output_root / run_id
    directory.mkdir(parents=True, exist_ok=False)
    rows: list[dict[str, float | int | str | None]] = []
    started = time.monotonic()
    deadline = started + args.duration_seconds
    next_sample = started
    while time.monotonic() < deadline:
        delay = next_sample - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        sample = capture(pid, mode)
        if sample is None:
            break
        if sample.identity != identity:
            fail(f"Process identity changed for PID {pid}; possible PID reuse")
        rows.append({
            "timestamp_utc": utc_now(),
            "elapsed_seconds": time.monotonic() - started,
            "cpu_percent": sample.cpu,
            "rss_kib": sample.rss,
            "vsz_kib": sample.vsz,
            "threads": sample.threads,
        })
        next_sample += args.interval_seconds
        if next_sample <= time.monotonic():
            next_sample = time.monotonic() + args.interval_seconds

    duration = time.monotonic() - started
    final = capture(pid, mode)
    alive = final is not None and final.identity == identity
    if not rows:
        fail("No process samples were collected")

    csv_path = directory / "samples.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    summary_path = directory / "summary.json"
    summary_path.write_text(
        json.dumps(summary(args, identity, selection, mode, rows, duration, alive),
                   indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return summary_path


def self_test() -> None:
    raw = (
        "4242 501 Fri Jul 24 10:11:12 2026 1.25 12345 67890 "
        "/Applications/Mac Vitals.app/Contents/MacOS/MacVitals\n"
    )
    sample = parse_ps(raw)
    assert sample.identity.executable_name == "MacVitals"
    assert sample.identity.started_at == "Fri Jul 24 10:11:12 2026"
    assert (sample.cpu, sample.rss, sample.vsz) == (1.25, 12345, 67890)
    assert len(sample.identity.token) == 64
    assert parse_pids("42\n41\n42\n") == [41, 42]
    assert percentile([1.0, 2.0, 3.0, 4.0], 0.95) == 4.0
    reused = Identity(4242, 501, "Fri Jul 24 10:12:13 2026", sample.identity.command)
    assert sample.identity != reused
    for invalid in ("4242 501 incomplete", ""):
        try:
            parse_ps(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid ps output was accepted")
    try:
        finite_nonnegative("nan", "CPU")
    except ValueError:
        pass
    else:
        raise AssertionError("NaN was accepted")
    print("Runtime process collector self-test passed")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("duration_seconds", nargs="?", type=positive_int,
                        default=positive_int(os.getenv("DURATION_SECONDS", "300")))
    parser.add_argument("interval_seconds", nargs="?", type=positive_float,
                        default=positive_float(os.getenv("INTERVAL_SECONDS", "2")))
    parser.add_argument("--process-name", default=os.getenv("PROCESS_NAME", "MacVitals"))
    parser.add_argument("--process-id", type=positive_int,
                        default=positive_int(os.environ["PROCESS_ID"])
                        if os.getenv("PROCESS_ID") else None)
    parser.add_argument("--expected-executable", type=Path,
                        default=Path(os.environ["EXPECTED_EXECUTABLE_PATH"])
                        if os.getenv("EXPECTED_EXECUTABLE_PATH") else None)
    parser.add_argument("--output-root", type=Path,
                        default=Path(os.getenv("OUTPUT_ROOT", "performance-results")))
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        self_test()
        return 0
    if not args.process_name or Path(args.process_name).name != args.process_name:
        fail(f"Process name must be a basename: {args.process_name!r}", 2)
    path = collect(args)
    print("Runtime metrics collection completed.")
    print(f"Runtime summary generated at {path}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
