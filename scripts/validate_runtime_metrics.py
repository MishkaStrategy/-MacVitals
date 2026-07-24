#!/usr/bin/env python3
"""Validate broad MacVitals CI runtime guardrails without claiming a benchmark."""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class Limits:
    minimum_samples: int = 10
    minimum_observed_seconds: float = 20.0
    maximum_mean_cpu_percent: float = 75.0
    maximum_p95_cpu_percent: float = 200.0
    maximum_rss_mib: float = 512.0
    maximum_rss_growth_mib: float = 128.0
    maximum_threads: float = 128.0
    maximum_interval_multiplier: float = 6.0


def nested(mapping: dict[str, Any], *keys: str) -> Any:
    value: Any = mapping
    for key in keys:
        if not isinstance(value, dict) or key not in value:
            raise ValueError(f"Missing field: {'.'.join(keys)}")
        value = value[key]
    return value


def finite_number(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{field} must be numeric, found {value!r}")
    result = float(value)
    if not math.isfinite(result):
        raise ValueError(f"{field} must be finite, found {value!r}")
    return result


def positive_integer(value: Any, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ValueError(f"{field} must be a positive integer, found {value!r}")
    return value


def nonnegative_integer(value: Any, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValueError(f"{field} must be a non-negative integer, found {value!r}")
    return value


def nonempty_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field} must be a non-empty string, found {value!r}")
    return value


def validate(summary: dict[str, Any], limits: Limits) -> list[str]:
    failures: list[str] = []

    try:
        schema = nested(summary, "schemaVersion")
        process_name = nested(summary, "process", "name")
        process_pid = positive_integer(
            nested(summary, "process", "pidAtStart"),
            "process.pidAtStart",
        )
        process_uid = nonnegative_integer(
            nested(summary, "process", "uidAtStart"),
            "process.uidAtStart",
        )
        started_at = nonempty_string(
            nested(summary, "process", "startedAt"),
            "process.startedAt",
        )
        executable_name = nonempty_string(
            nested(summary, "process", "executableName"),
            "process.executableName",
        )
        identity_token = nonempty_string(
            nested(summary, "process", "identityTokenSha256"),
            "process.identityTokenSha256",
        )
        identity_stable = nested(summary, "process", "identityStable")
        alive_at_end = nested(summary, "process", "aliveAtEnd")
        selection_mode = nonempty_string(
            nested(summary, "process", "selectionMode"),
            "process.selectionMode",
        )
        requested_duration = finite_number(
            nested(summary, "requested", "durationSeconds"),
            "requested.durationSeconds",
        )
        requested_interval = finite_number(
            nested(summary, "requested", "intervalSeconds"),
            "requested.intervalSeconds",
        )
        observed_clock = nested(summary, "observed", "clock")
        sample_source = nested(summary, "observed", "sampleSource")
        observed_duration = finite_number(
            nested(summary, "observed", "durationSeconds"),
            "observed.durationSeconds",
        )
        first_sample_elapsed = finite_number(
            nested(summary, "observed", "firstSampleElapsedSeconds"),
            "observed.firstSampleElapsedSeconds",
        )
        last_sample_elapsed = finite_number(
            nested(summary, "observed", "lastSampleElapsedSeconds"),
            "observed.lastSampleElapsedSeconds",
        )
        sample_count = finite_number(
            nested(summary, "observed", "sampleCount"),
            "observed.sampleCount",
        )
        interval_p95_raw = nested(
            summary,
            "observed",
            "sampleIntervalSeconds",
            "p95",
        )
        interval_p95 = (
            None
            if interval_p95_raw is None
            else finite_number(interval_p95_raw, "observed.sampleIntervalSeconds.p95")
        )
        mean_cpu = finite_number(
            nested(summary, "metrics", "cpuPercent", "mean"),
            "metrics.cpuPercent.mean",
        )
        p95_cpu = finite_number(
            nested(summary, "metrics", "cpuPercent", "p95"),
            "metrics.cpuPercent.p95",
        )
        rss_max_kib = finite_number(
            nested(summary, "metrics", "residentMemoryKiB", "max"),
            "metrics.residentMemoryKiB.max",
        )
        rss_growth_kib = finite_number(
            nested(summary, "metrics", "residentMemoryKiB", "growth"),
            "metrics.residentMemoryKiB.growth",
        )
        thread_max_raw = nested(summary, "metrics", "threads", "max")
        thread_max = (
            None
            if thread_max_raw is None
            else finite_number(thread_max_raw, "metrics.threads.max")
        )
    except ValueError as error:
        return [str(error)]

    if schema != 3:
        failures.append(f"Expected schemaVersion 3, found {schema!r}")
    if process_name != "MacVitals":
        failures.append(f"Expected process name MacVitals, found {process_name!r}")
    if executable_name != "MacVitals":
        failures.append(
            f"Expected executable name MacVitals, found {executable_name!r}"
        )
    if process_pid <= 0 or process_uid < 0 or not started_at:
        failures.append("Process identity fields must be populated")
    if not re.fullmatch(r"[0-9a-f]{64}", identity_token):
        failures.append("Process identity token must be a lowercase SHA-256 digest")
    if identity_stable is not True:
        failures.append("Process identity was not stable for the entire collection")
    if alive_at_end is not True:
        failures.append("MacVitals exited before the runtime collection completed")
    if selection_mode not in {"explicit-pid", "exact-name-single-match"}:
        failures.append(f"Unexpected process selection mode: {selection_mode!r}")
    if observed_clock != "monotonic":
        failures.append(f"Expected monotonic elapsed clock, found {observed_clock!r}")
    if sample_source != "locale-fixed-single-ps-snapshot":
        failures.append(f"Unexpected runtime sample source: {sample_source!r}")
    if requested_duration <= 0 or requested_interval <= 0:
        failures.append("Requested duration and interval must be positive")
    if first_sample_elapsed < 0 or last_sample_elapsed < first_sample_elapsed:
        failures.append("Observed elapsed sample bounds are invalid")
    if observed_duration < last_sample_elapsed:
        failures.append("Observed duration is shorter than the final sample timestamp")
    if sample_count < limits.minimum_samples:
        failures.append(
            f"Only {int(sample_count)} samples were collected; "
            f"minimum is {limits.minimum_samples}"
        )
    if observed_duration < limits.minimum_observed_seconds:
        failures.append(
            f"Observed duration {observed_duration:.1f}s is below "
            f"{limits.minimum_observed_seconds:.1f}s"
        )
    if interval_p95 is not None:
        interval_limit = requested_interval * limits.maximum_interval_multiplier + 1.0
        if interval_p95 > interval_limit:
            failures.append(
                f"p95 sample interval {interval_p95:.2f}s exceeds "
                f"guardrail {interval_limit:.2f}s"
            )
    if mean_cpu > limits.maximum_mean_cpu_percent:
        failures.append(
            f"Mean CPU {mean_cpu:.2f}% exceeds "
            f"guardrail {limits.maximum_mean_cpu_percent:.2f}%"
        )
    if p95_cpu > limits.maximum_p95_cpu_percent:
        failures.append(
            f"p95 CPU {p95_cpu:.2f}% exceeds "
            f"guardrail {limits.maximum_p95_cpu_percent:.2f}%"
        )

    rss_max_mib = rss_max_kib / 1024.0
    rss_growth_mib = rss_growth_kib / 1024.0
    if rss_max_mib > limits.maximum_rss_mib:
        failures.append(
            f"Peak RSS {rss_max_mib:.2f} MiB exceeds "
            f"guardrail {limits.maximum_rss_mib:.2f} MiB"
        )
    if rss_growth_mib > limits.maximum_rss_growth_mib:
        failures.append(
            f"RSS growth {rss_growth_mib:.2f} MiB exceeds "
            f"guardrail {limits.maximum_rss_growth_mib:.2f} MiB"
        )
    if thread_max is not None and thread_max > limits.maximum_threads:
        failures.append(
            f"Thread count {thread_max:.0f} exceeds "
            f"guardrail {limits.maximum_threads:.0f}"
        )

    return failures


def load_summary(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise SystemExit(f"Could not read runtime summary {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise SystemExit(f"Runtime summary is not valid JSON: {error}") from error
    if not isinstance(value, dict):
        raise SystemExit("Runtime summary root must be an object")
    return value


def self_test() -> None:
    passing = {
        "schemaVersion": 3,
        "process": {
            "name": "MacVitals",
            "pidAtStart": 4242,
            "uidAtStart": 501,
            "startedAt": "Fri Jul 24 10:11:12 2026",
            "executableName": "MacVitals",
            "identityTokenSha256": "a" * 64,
            "identityStable": True,
            "aliveAtEnd": True,
            "selectionMode": "explicit-pid",
        },
        "requested": {"durationSeconds": 45, "intervalSeconds": 2},
        "observed": {
            "clock": "monotonic",
            "sampleSource": "locale-fixed-single-ps-snapshot",
            "durationSeconds": 45,
            "firstSampleElapsedSeconds": 0.1,
            "lastSampleElapsedSeconds": 44.1,
            "sampleCount": 22,
            "sampleIntervalSeconds": {"p95": 3},
        },
        "metrics": {
            "cpuPercent": {"mean": 2, "p95": 10},
            "residentMemoryKiB": {"max": 100_000, "growth": 2_000},
            "threads": {"max": 12},
        },
    }
    assert validate(passing, Limits()) == []

    reused = json.loads(json.dumps(passing))
    reused["process"]["identityStable"] = False
    assert any("identity" in failure for failure in validate(reused, Limits()))

    wall_clock = json.loads(json.dumps(passing))
    wall_clock["observed"]["clock"] = "wall"
    assert any("monotonic" in failure for failure in validate(wall_clock, Limits()))

    ambiguous = json.loads(json.dumps(passing))
    ambiguous["process"]["selectionMode"] = "first-name-match"
    assert any("selection" in failure for failure in validate(ambiguous, Limits()))

    exiting = json.loads(json.dumps(passing))
    exiting["process"]["aliveAtEnd"] = False
    assert any("exited" in failure for failure in validate(exiting, Limits()))

    runaway = json.loads(json.dumps(passing))
    runaway["metrics"]["residentMemoryKiB"]["max"] = 900 * 1024
    assert any("Peak RSS" in failure for failure in validate(runaway, Limits()))

    malformed = json.loads(json.dumps(passing))
    del malformed["metrics"]["cpuPercent"]
    assert validate(malformed, Limits())
    print("Runtime metrics validator self-test passed")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("summary", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--minimum-samples", type=int, default=Limits.minimum_samples)
    parser.add_argument(
        "--minimum-observed-seconds",
        type=float,
        default=Limits.minimum_observed_seconds,
    )
    parser.add_argument(
        "--maximum-mean-cpu-percent",
        type=float,
        default=Limits.maximum_mean_cpu_percent,
    )
    parser.add_argument(
        "--maximum-p95-cpu-percent",
        type=float,
        default=Limits.maximum_p95_cpu_percent,
    )
    parser.add_argument("--maximum-rss-mib", type=float, default=Limits.maximum_rss_mib)
    parser.add_argument(
        "--maximum-rss-growth-mib",
        type=float,
        default=Limits.maximum_rss_growth_mib,
    )
    parser.add_argument(
        "--maximum-threads",
        type=float,
        default=Limits.maximum_threads,
    )
    parser.add_argument(
        "--maximum-interval-multiplier",
        type=float,
        default=Limits.maximum_interval_multiplier,
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        self_test()
        return 0
    if args.summary is None:
        raise SystemExit("A runtime summary path is required unless --self-test is used")

    limits = Limits(
        minimum_samples=max(1, args.minimum_samples),
        minimum_observed_seconds=max(0, args.minimum_observed_seconds),
        maximum_mean_cpu_percent=max(0, args.maximum_mean_cpu_percent),
        maximum_p95_cpu_percent=max(0, args.maximum_p95_cpu_percent),
        maximum_rss_mib=max(1, args.maximum_rss_mib),
        maximum_rss_growth_mib=max(0, args.maximum_rss_growth_mib),
        maximum_threads=max(1, args.maximum_threads),
        maximum_interval_multiplier=max(1, args.maximum_interval_multiplier),
    )
    summary = load_summary(args.summary)
    failures = validate(summary, limits)
    if failures:
        print("Runtime guardrail FAILED:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    observed = summary["observed"]
    metrics = summary["metrics"]
    print("Runtime guardrail passed")
    print(
        "samples={samples} duration={duration:.1f}s mean_cpu={cpu:.2f}% "
        "peak_rss={rss:.2f}MiB rss_growth={growth:.2f}MiB".format(
            samples=observed["sampleCount"],
            duration=float(observed["durationSeconds"]),
            cpu=float(metrics["cpuPercent"]["mean"]),
            rss=float(metrics["residentMemoryKiB"]["max"]) / 1024.0,
            growth=float(metrics["residentMemoryKiB"]["growth"]) / 1024.0,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
