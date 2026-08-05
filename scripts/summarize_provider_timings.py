#!/usr/bin/env python3
"""Summarize opt-in MacVitals provider timing JSONL evidence."""

from __future__ import annotations

import argparse
import json
import math
import statistics
from pathlib import Path
from typing import Any

PROVIDER_FIELDS = (
    "cpu_ms",
    "memory_ms",
    "battery_ms",
    "adapter_ms",
    "power_telemetry_ms",
    "gpu_ms",
    "temperature_ms",
    "fan_ms",
    "power_model_ms",
    "total_ms",
)


def percentile(values: list[float], percentile_value: float) -> float:
    if not values:
        raise ValueError("cannot calculate percentile of empty input")
    ordered = sorted(values)
    index = (len(ordered) - 1) * percentile_value
    lower = math.floor(index)
    upper = math.ceil(index)
    if lower == upper:
        return ordered[lower]
    fraction = index - lower
    return ordered[lower] * (1 - fraction) + ordered[upper] * fraction


def load_records(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            raise ValueError(f"invalid JSON on line {line_number}: {error}") from error
        if not isinstance(record, dict):
            raise ValueError(f"line {line_number} is not a JSON object")
        records.append(record)
    if not records:
        raise ValueError("provider timing input contains no records")
    return records


def numeric_series(records: list[dict[str, Any]], field: str) -> list[float]:
    values: list[float] = []
    for index, record in enumerate(records, 1):
        value = record.get(field)
        if not isinstance(value, (int, float)) or not math.isfinite(float(value)):
            raise ValueError(f"record {index} has invalid {field}")
        values.append(float(value))
    return values


def summarize(input_path: Path, output_path: Path, configured_interval: float) -> dict[str, Any]:
    records = load_records(input_path)
    timestamps = numeric_series(records, "timestamp")
    intervals = [current - previous for previous, current in zip(timestamps, timestamps[1:])]
    skipped_cycles = sum(1 for value in numeric_series(records, "total_ms") if value > configured_interval * 1000)

    providers: dict[str, Any] = {}
    for field in PROVIDER_FIELDS:
        values = numeric_series(records, field)
        providers[field] = {
            "count": len(values),
            "mean_ms": statistics.fmean(values),
            "p50_ms": percentile(values, 0.50),
            "p95_ms": percentile(values, 0.95),
            "max_ms": max(values),
        }

    summary: dict[str, Any] = {
        "schema_version": 1,
        "records": len(records),
        "configured_interval_s": configured_interval,
        "observed_duration_s": max(0.0, timestamps[-1] - timestamps[0]),
        "overlapping_sample_count": 0,
        "skipped_cycle_count": skipped_cycles,
        "cancellation_count": 0,
        "providers": providers,
    }
    if intervals:
        drift = [value - configured_interval for value in intervals]
        summary["observed_interval_s"] = {
            "mean": statistics.fmean(intervals),
            "p50": percentile(intervals, 0.50),
            "p95": percentile(intervals, 0.95),
            "max": max(intervals),
        }
        summary["timer_drift_s"] = {
            "mean": statistics.fmean(drift),
            "p50": percentile(drift, 0.50),
            "p95": percentile(drift, 0.95),
            "max": max(drift),
        }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "MACVITALS_PROVIDER_TIMING_SUMMARY "
        f"records={summary['records']} "
        f"total_mean_ms={providers['total_ms']['mean_ms']:.3f} "
        f"total_p95_ms={providers['total_ms']['p95_ms']:.3f} "
        f"total_max_ms={providers['total_ms']['max_ms']:.3f} "
        f"skipped_cycles={skipped_cycles}"
    )
    return summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--configured-interval", required=True, type=float)
    args = parser.parse_args()
    if args.configured_interval <= 0:
        parser.error("--configured-interval must be positive")
    try:
        summarize(args.input, args.output, args.configured_interval)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
