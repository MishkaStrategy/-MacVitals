# Architecture

MacVitals separates domain models, sensor providers, monitoring, power evaluation, menu bar presentation, persistence and diagnostics.

- `MetricValue` carries value, unit, availability, quality, source, timestamp and estimation status.
- Providers never invent missing values and do not decide UI presentation.
- `MetricsCoordinator` owns the sampling lifecycle and publishes immutable snapshots.
- `ChargerSufficiencyEvaluator` is a pure value type covered by deterministic tests.
- AppKit owns `NSStatusItem`/`NSPopover`; SwiftUI renders content and settings.
- Bounded ring buffers keep only short-term in-memory history.
- Sleep invalidates CPU baselines, resets the power window and inserts a graph discontinuity.

The v1 build intentionally targets Apple Silicon (`arm64`) only. XcodeGen, local commands, CI, packaging and release verification share this architecture contract; universal and Intel executables are rejected.

The v1 build intentionally avoids private GPU utilization APIs, subprocess sampling, root helpers, databases and network services.
