#!/usr/bin/env python3
"""Render stable CPU/RSS evidence from collect_runtime_metrics.py summaries."""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import tempfile
from pathlib import Path
from typing import Any, NoReturn

SCENARIO_RE = re.compile(r"[A-Za-z0-9._-]+\Z")
SHA_RE = re.compile(r"(?:[0-9a-f]{40}|unknown)\Z")


def fail(message: str) -> NoReturn:
    raise SystemExit(message)


def finite_number(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        fail(f"Runtime summary field {field} must be numeric")
    result = float(value)
    if not math.isfinite(result):
        fail(f"Runtime summary field {field} must be finite")
    return result


def positive_integer(value: Any, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        fail(f"Runtime summary field {field} must be a positive integer")
    return value


def nested(summary: dict[str, Any], *keys: str) -> Any:
    value: Any = summary
    for key in keys:
        if not isinstance(value, dict) or key not in value:
            fail("Runtime summary is missing " + ".".join(keys))
        value = value[key]
    return value


def mib(kib: float) -> float:
    return kib / 1024.0


def build_report(summary: dict[str, Any], scenario: str, source_sha: str) -> dict[str, Any]:
    if not SCENARIO_RE.fullmatch(scenario):
        fail("Scenario must contain only letters, digits, dot, underscore or hyphen")
    if not SHA_RE.fullmatch(source_sha):
        fail("Source SHA must be a full lowercase SHA-1 or 'unknown'")

    sample_count = positive_integer(nested(summary, "observed", "sampleCount"), "observed.sampleCount")
    duration = finite_number(nested(summary, "observed", "durationSeconds"), "observed.durationSeconds")
    if duration <= 0:
        fail("Runtime summary duration must be positive")

    cpu = nested(summary, "metrics", "cpuPercent")
    rss = nested(summary, "metrics", "residentMemoryKiB")
    if not isinstance(cpu, dict) or not isinstance(rss, dict):
        fail("Runtime summary CPU and RSS metrics must be objects")

    cpu_mean = finite_number(cpu.get("mean"), "metrics.cpuPercent.mean")
    cpu_p95 = finite_number(cpu.get("p95"), "metrics.cpuPercent.p95")
    cpu_max = finite_number(cpu.get("max"), "metrics.cpuPercent.max")
    rss_mean = finite_number(rss.get("mean"), "metrics.residentMemoryKiB.mean")
    rss_p95 = finite_number(rss.get("p95"), "metrics.residentMemoryKiB.p95")
    rss_peak = finite_number(rss.get("max"), "metrics.residentMemoryKiB.max")
    rss_first = finite_number(rss.get("first"), "metrics.residentMemoryKiB.first")
    rss_last = finite_number(rss.get("last"), "metrics.residentMemoryKiB.last")
    rss_growth = finite_number(rss.get("growth"), "metrics.residentMemoryKiB.growth")

    process = nested(summary, "process")
    if not isinstance(process, dict):
        fail("Runtime summary process must be an object")
    if process.get("name") != "MacVitals":
        fail("Runtime summary must describe the MacVitals process")
    if process.get("identityStable") is not True:
        fail("Runtime summary process identity is not stable")

    threads = nested(summary, "metrics", "threads")
    thread_values: dict[str, float | None] = {"mean": None, "p95": None, "max": None}
    if isinstance(threads, dict):
        for key in thread_values:
            value = threads.get(key)
            if value is not None:
                thread_values[key] = finite_number(value, f"metrics.threads.{key}")

    return {
        "schemaVersion": 1,
        "scenario": scenario,
        "sourceSha": source_sha,
        "process": {
            "name": "MacVitals",
            "identityStable": True,
            "aliveAtEnd": process.get("aliveAtEnd") is True,
        },
        "measurement": {
            "durationSeconds": duration,
            "sampleCount": sample_count,
            "cpuPercent": {
                "mean": cpu_mean,
                "p95": cpu_p95,
                "max": cpu_max,
            },
            "residentMemoryMiB": {
                "mean": mib(rss_mean),
                "p95": mib(rss_p95),
                "peak": mib(rss_peak),
                "first": mib(rss_first),
                "last": mib(rss_last),
                "growth": mib(rss_growth),
            },
            "threads": thread_values,
        },
    }


def summary_line(report: dict[str, Any]) -> str:
    measurement = report["measurement"]
    cpu = measurement["cpuPercent"]
    rss = measurement["residentMemoryMiB"]
    fields = [
        "MACVITALS_RESOURCE_SUMMARY",
        f"scenario={report['scenario']}",
        f"source_sha={report['sourceSha']}",
        f"samples={measurement['sampleCount']}",
        f"duration_s={measurement['durationSeconds']:.3f}",
        f"cpu_mean_pct={cpu['mean']:.3f}",
        f"cpu_p95_pct={cpu['p95']:.3f}",
        f"cpu_max_pct={cpu['max']:.3f}",
        f"rss_mean_mib={rss['mean']:.3f}",
        f"rss_p95_mib={rss['p95']:.3f}",
        f"rss_peak_mib={rss['peak']:.3f}",
        f"rss_first_mib={rss['first']:.3f}",
        f"rss_last_mib={rss['last']:.3f}",
        f"rss_growth_mib={rss['growth']:.3f}",
    ]
    threads = measurement["threads"]
    if threads["max"] is not None:
        fields.extend(
            [
                f"threads_mean={threads['mean']:.3f}",
                f"threads_p95={threads['p95']:.3f}",
                f"threads_max={threads['max']:.3f}",
            ]
        )
    return " ".join(fields)


def markdown(report: dict[str, Any]) -> str:
    measurement = report["measurement"]
    cpu = measurement["cpuPercent"]
    rss = measurement["residentMemoryMiB"]
    lines = [
        "## MacVitals process resources",
        "",
        f"Scenario: `{report['scenario']}`  ",
        f"Source SHA: `{report['sourceSha']}`",
        "",
        "| Metric | Mean | p95 | Peak / max |",
        "|---|---:|---:|---:|",
        f"| CPU | {cpu['mean']:.2f}% | {cpu['p95']:.2f}% | {cpu['max']:.2f}% |",
        f"| Resident memory | {rss['mean']:.2f} MiB | {rss['p95']:.2f} MiB | {rss['peak']:.2f} MiB |",
        "",
        f"Samples: **{measurement['sampleCount']}** over **{measurement['durationSeconds']:.1f} s**.  ",
        f"RSS first/last/growth: **{rss['first']:.2f} / {rss['last']:.2f} / {rss['growth']:+.2f} MiB**.",
        "",
    ]
    return "\n".join(lines)


def run(summary_path: Path, scenario: str, source_sha: str, output_path: Path | None) -> int:
    try:
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"Could not read runtime summary: {error}")
    if not isinstance(summary, dict):
        fail("Runtime summary must contain a JSON object")

    report = build_report(summary, scenario, source_sha)
    target = output_path or summary_path.with_name("resource-summary.json")
    target.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(summary_line(report))

    step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary:
        with Path(step_summary).open("a", encoding="utf-8") as handle:
            handle.write(markdown(report))
    return 0


def self_test() -> None:
    payload = {
        "process": {"name": "MacVitals", "identityStable": True, "aliveAtEnd": True},
        "observed": {"durationSeconds": 60.25, "sampleCount": 31},
        "metrics": {
            "cpuPercent": {"mean": 2.5, "p95": 9.5, "max": 12.0},
            "residentMemoryKiB": {
                "mean": 81920.0,
                "p95": 82944.0,
                "max": 83968.0,
                "first": 80896.0,
                "last": 81920.0,
                "growth": 1024.0,
            },
            "threads": {"mean": 5.0, "p95": 6.0, "max": 7.0},
        },
    }
    report = build_report(payload, "self-test", "0" * 40)
    line = summary_line(report)
    assert line.startswith("MACVITALS_RESOURCE_SUMMARY ")
    assert "cpu_max_pct=12.000" in line
    assert "rss_peak_mib=82.000" in line
    assert report["measurement"]["residentMemoryMiB"]["growth"] == 1.0
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        source = root / "summary.json"
        target = root / "resource-summary.json"
        source.write_text(json.dumps(payload), encoding="utf-8")
        assert run(source, "self-test", "0" * 40, target) == 0
        assert target.is_file()
    print("Runtime resource reporter self-test passed")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    result.add_argument("summary", nargs="?", type=Path)
    result.add_argument("--scenario", default="runtime-test")
    result.add_argument("--source-sha", default="unknown")
    result.add_argument("--output", type=Path)
    result.add_argument("--self-test", action="store_true")
    return result


def main() -> int:
    args = parser().parse_args()
    if args.self_test:
        self_test()
        return 0
    if args.summary is None:
        fail("A runtime summary path is required")
    return run(args.summary, args.scenario, args.source_sha, args.output)


if __name__ == "__main__":
    raise SystemExit(main())
