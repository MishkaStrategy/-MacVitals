#!/usr/bin/env python3
"""Validate the accepted shared-process-sampling topology without product instrumentation."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CENTER = ROOT / "MacVitals/UI/Overview/ProcessConsumersView.swift"
HISTORY = ROOT / "MacVitals/History/HistoricalConsumptionCenter.swift"
PRESENTER = ROOT / "MacVitals/UI/Overview/MetricDetailWindowPresenter.swift"


def read(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f"shared sampling contract file is missing or unsafe: {path}")
    return path.read_text(encoding="utf-8")


def require(text: str, marker: str, label: str) -> None:
    if marker not in text:
        raise SystemExit(f"shared sampling contract is missing {label}: {marker}")


def reject(text: str, marker: str, label: str) -> None:
    if marker in text:
        raise SystemExit(f"shared sampling contract contains forbidden {label}: {marker}")


def validate() -> None:
    center = read(CENTER)
    history = read(HISTORY)
    presenter = read(PRESENTER)

    for marker, label in (
        ("actor ProcessMetricsSamplingCenter", "sampling center actor"),
        ("static let shared = ProcessMetricsSamplingCenter()", "shared center singleton"),
        ("private var inFlight: InFlightSample?", "single in-flight slot"),
        ("if let activeSample = inFlight", "in-flight join path"),
        ("return cachedSnapshot", "shared cache return"),
        ("publishIfCurrent(snapshot, from: activeSample)", "generation/request publication guard"),
        ("private let center = ProcessMetricsSamplingCenter.shared", "live consumer shared center"),
    ):
        require(center, marker, label)

    for marker, label in (
        ("private let center = ProcessMetricsSamplingCenter.shared", "historical shared center"),
        ("await center.subscribe(subscriberID)", "historical subscription"),
        ("let snapshot = await center.sample(", "historical shared sample"),
        ("await store.record(snapshot: snapshot, elapsed: elapsed)", "historical shared snapshot persistence"),
    ):
        require(history, marker, label)
    reject(history, "ProcessMetricsProvider()", "independent historical provider")

    for marker, label in (
        ("private var windowController: NSWindowController?", "single primary detail controller"),
        ("if let window = windowController?.window", "primary detail reuse path"),
        ("window.contentViewController = hostingController", "primary detail replacement path"),
    ):
        require(presenter, marker, label)

    print("Shared process sampling topology contract passed")


def self_test() -> None:
    require("alpha beta", "beta", "fixture marker")
    try:
        require("alpha", "beta", "fixture marker")
    except SystemExit:
        pass
    else:
        raise AssertionError("missing required marker fixture was not rejected")
    try:
        reject("alpha beta", "beta", "fixture marker")
    except SystemExit:
        pass
    else:
        raise AssertionError("forbidden marker fixture was not rejected")
    print("Shared process sampling topology self-test passed")


if __name__ == "__main__":
    import sys

    if sys.argv[1:] == ["--self-test"]:
        self_test()
    elif sys.argv[1:]:
        raise SystemExit("usage: validate_shared_process_sampling_contract.py [--self-test]")
    else:
        self_test()
        validate()
