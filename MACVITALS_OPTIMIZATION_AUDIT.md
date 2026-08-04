# MacVitals Optimization Audit

Status: **initial audit complete; no product code changed**  
Tracking issue: #48  
Audit branch: `audit/macvitals-optimization-baseline`  
Canonical product base: `feature/macvitals-v1`  
Exact audited product source SHA: `fe97c56e458b3a9dc67cab8451737bc6945703f5`  
Default branch observed during audit: `main` at `cb51ada962e946829630adea7a41c80950bfa6ae`

## 1. Scope and evidence policy

This document is an incremental audit, not a restart of the twenty historical optimization rounds already stored under `docs/optimization/round-01.md` through `round-20.md`.

The previous documented hosted regression checkpoint is `d4a6da91c30e94db1add397d7387a0805c8cca69`, with 0.233% mean CPU, 0.7% p95 CPU, 53.53 MiB peak RSS and five peak threads in a short hosted Apple Silicon run. Those numbers remain useful historical regression evidence, but they are **not** accepted as the baseline for the current audited SHA because:

- the audited product source has moved to `fe97c56e458b3a9dc67cab8451737bc6945703f5`;
- HUD and related product work has continued after the old checkpoint;
- hosted measurements do not prove physical wakeups, Energy Impact, battery runtime, sleep/wake behavior or multi-hour stability;
- no current exact-head Instruments evidence was produced during this documentation-only task.

Therefore every optimization issue created from this audit must either establish an exact-head baseline first or provide a deterministic structural proof that is independently testable.

## 2. Repository and branch state

### Canonical base selected

`feature/macvitals-v1` is the current product base used by active stacked product work. It resolves to exact SHA:

`fe97c56e458b3a9dc67cab8451737bc6945703f5`

The default branch `main` is not used as the optimization base and is not modified.

### Active work that must not be overwritten

The audit identified active Draft work that must be treated as protected:

- PR #27 — ProcessMetricsProvider stack-corruption fix and live regression test;
- PR #35 — configurable notch HUD sensors and appearance;
- PR #37 — one/two contour indicators around the notch;
- PR #38, #39 and #40 — physical HUD preview/validation harnesses;
- PR #47 — repository-wide exact self-hosted runner selector enforcement.

The repository also contains unmerged preview branches for:

- power-aware sampling intervals;
- network traffic;
- storage usage;
- network/storage history;
- historical consumption leaders.

These preview branches diverge from the audited product base. Their code is analyzed below where relevant, but no optimization implementation should be stacked on them until an integration base is explicitly chosen.

### CI status caveat

The GitHub connector returned no combined status contexts or pull-request workflow runs for exact product SHA `fe97c56e458b3a9dc67cab8451737bc6945703f5`. This does not prove failure; it means the audit cannot claim a fresh exact-head build/test result for that SHA.

All future MacVitals optimization workflows must use the repository-approved self-hosted selectors. GitHub-hosted measurements are not an acceptable new validation path.

## 3. Architecture map

### Application lifecycle

`MacVitals/App/AppDelegate.swift`

- creates `SettingsStore`, `MetricsCoordinator`, `FanControlClient` and `NotificationCoordinator`;
- creates `StatusItemController`;
- starts the coordinator and lifecycle monitor;
- routes snapshots to notifications;
- restores fan control to automatic mode and cancels monitoring during termination.

### Domain and snapshot model

`MacVitals/Domain/MetricModels.swift`

- provider values are normalized into immutable `MetricValue<T>` values;
- `SystemSnapshot` is the central live value passed to UI, menu-bar rendering, notifications and diagnostics;
- unavailable data is represented explicitly rather than fabricated.

### Sampling core

`MacVitals/Monitoring/SystemSampler.swift`

- actor-isolated synchronous provider coordinator;
- sequentially samples CPU, memory, battery, adapter, direct power telemetry, GPU, temperature and fans;
- evaluates the power model;
- returns one immutable snapshot and partial provider timing information.

`MacVitals/Monitoring/MetricsCoordinator.swift`

- `@MainActor ObservableObject`;
- owns the single core sampling `Task`;
- publishes the latest snapshot, sampling health and all short-term histories;
- inserts graph discontinuities on sleep;
- restarts sampling on wake.

### Providers

- CPU: Mach host counters with a resettable delta baseline;
- memory: VM and memory-pressure state;
- battery/adapter/power: IOKit and derived power model;
- GPU: Metal capability reporting without fabricated whole-system utilization;
- temperature: AppleSMC plus battery temperature, with a five-second internal SMC cache;
- fans: AppleSMC read-only values;
- processes: per-process delta sampling and application aggregation.

### UI and AppKit boundary

- `StatusItemController` owns `NSStatusItem`, `NSPopover`, status-bar bitmap rendering and notch HUD updates;
- SwiftUI `OverviewView` observes the broad coordinator and settings objects;
- detail windows are created through presenters and observe the same coordinator;
- process-consumer detail content creates its own `ProcessConsumersMonitor`;
- Charts are fed by transformed history arrays.

### Persistence

Current audited product base:

- `SettingsStore` persists user settings through `UserDefaults`;
- live metric history is in memory only through `RingBuffer`;
- normal operation has no periodic metric-history disk write.

Historical consumption preview branch:

- `HistoricalConsumptionCenter` runs a separate process sampling loop;
- `HistoricalConsumptionArchiveStore` retains five-minute buckets for seven days;
- archive schema is JSON v1;
- the complete archive is encoded and atomically rewritten at most once per minute.

## 4. Sampling and task map

| Loop / task | Owner | Trigger / interval | Main work | Current observation |
|---|---|---|---|---|
| Core metric loop | `MetricsCoordinator` | 1/2/5/10/15/30 s | complete `SystemSampler.sample()` | one loop, but almost all providers share one cadence |
| Temperature SMC refresh | `TemperatureProvider` | minimum 5 s | up to 48 SMC sensor reads | internally cached; still invoked every core sample |
| Fan sampling | `FanProvider` | every core sample | `FNum` plus current/target/min/max/mode keys per fan | no provider-level cadence cache |
| Status item render | `StatusItemController` | every published snapshot/settings change | formats values and allocates a new bitmap image | must be profiled before caching policy is chosen |
| Per-detail process loop | `ProcessConsumersMonitor` | active detail window interval | enumerates running apps and samples processes | one independent provider/task per open detail view |
| Historical process loop | `HistoricalConsumptionCenter` preview | configured interval | repeats running-app enumeration and process sampling | duplicates live process monitoring when both are active |
| Network loop | `NetworkTrafficMonitor` preview | >=1 s while consumers exist | `getifaddrs`, history append/prune | shared consumer count avoids one task per view |
| Storage loop | `StorageUsageMonitor` preview | >=5 s while consumers exist | filesystem attributes and history append/prune | shared consumer count; cadence still linked to UI setting |
| Lifecycle handling | `LifecycleMonitor` | sleep/wake notifications | stop/reset/restart and discontinuity | behavior is explicitly modeled and tested |

## 5. Data-flow map

```text
System APIs / AppleSMC / Metal
          |
          v
     SystemSampler actor
          |
          v
   immutable SampleResult
          |
          v
MetricsCoordinator @MainActor
   |        |         |
   |        |         +--> notifications / diagnostics
   |        +------------> status item bitmap + notch HUD
   +---------------------> overview and detail SwiftUI trees
                             |
                             +--> repeated history filtering/segmentation

ProcessMetricsProvider
   |-- ProcessConsumersMonitor per detail window
   `-- HistoricalConsumptionCenter preview
          |
          `--> HistoricalConsumptionArchiveStore actor
                 `--> full JSON atomic rewrite
```

## 6. Confirmed bottlenecks and correctness-preserving optimization opportunities

### A. Missing exact-head baseline and incomplete provider timings — P0

`SystemSampler` measures CPU, memory, battery, adapter, GPU, fans and power-model evaluation, but does not separately measure:

- direct system-power telemetry;
- complete temperature sampling;
- snapshot construction/publication;
- menu-bar rendering;
- history publication;
- process-monitor sampling;
- archive encoding and disk write.

No fresh physical baseline exists for exact audited SHA. This blocks evidence-based cadence changes.

Expected value: enables all later work to be accepted or rejected with exact-head evidence.  
Risk: low if signposts and metrics remain test-only or opt-in.  
Complexity: medium.  
Verification: exact self-hosted ARM64 Release build, XCTest metrics, Instruments Time Profiler/Allocations/Leaks/System Trace or supported energy evidence, closed/open popover profiles and sleep/wake run.

### B. `RingBuffer` is not O(1) after capacity is reached — P1

`RingBuffer.append` calls `storage.removeFirst()` when full. Swift Array removal at the front shifts the remaining elements. At maximum capacity 3,600 this is linear work and memory movement for every appended history point after the first hour fills.

The issue multiplies across CPU, memory, GPU, battery, temperature, power channels, sensor dictionaries and fan dictionaries.

Expected value: remove recurring history-array shifts and reduce allocations/copies.  
Risk: medium because ordering, capacity and discontinuity semantics must remain exact.  
Complexity: medium.  
Verification: deterministic ring-buffer tests, allocation benchmark, append throughput benchmark and graph-history equivalence tests.

### C. Complete history arrays are copied and separately published every core sample — P1

`MetricsCoordinator.publishHistory()` materializes `.values` for every buffer, maps all sensor/fan buffers to arrays and assigns ten separate `@Published` properties after every sample.

Consequences:

- repeated array copying up to capacity;
- multiple Combine change notifications per sample;
- broad `EnvironmentObject` invalidation;
- work occurs on `MainActor`;
- detail histories are rebuilt even when no corresponding chart/window is visible.

Expected value: lower MainActor time, allocations and SwiftUI invalidation.  
Risk: high because graph behavior, sleep discontinuities and accessibility must remain unchanged.  
Complexity: medium/high.  
Verification: publish-count instrumentation, SwiftUI update counts, UI regression tests for all ranges, memory/allocation comparison and exact history equivalence.

### D. Expensive providers share the core cadence — P1 measurement-gated

`SystemSampler` sequentially invokes all providers on every core cycle. Temperature protects SMC reads with a five-second cache, but fan sampling reads multiple SMC keys every cycle and other IOKit providers have no visible cadence tier in the coordinator.

This is a confirmed architectural limitation, but the optimal cadence is not yet proven. Implementation must follow provider-latency and wakeup measurement rather than a guessed interval.

Expected value: fewer SMC/IOKit calls and wakeups at 1–2 second UI intervals.  
Risk: high because stale data, thermal/fan safety display and power-source transitions must remain correct.  
Complexity: high.  
Verification: per-provider timing distributions, call counts, wakeups, freshness tests, power-source transitions and sleep/wake recovery.

### E. Process sampling is duplicated across consumers — P1

Each `MetricDetailView` owns a new `ProcessConsumersMonitor`, which owns its own `ProcessMetricsProvider` and task. Opening several eligible detail windows can therefore enumerate running applications and sample the same processes independently.

The historical consumption preview adds another global `HistoricalConsumptionCenter` with a separate `ProcessMetricsProvider`, running-app enumeration and sampling loop.

Expected value: one process sample can serve live CPU/memory/GPU/energy ranking and historical aggregation.  
Risk: high because delta baselines, PID reuse checks, window lifetime and history continuity are sensitive.  
Complexity: high.  
Verification: provider call-count tests, multi-window physical test, exact ranking equivalence, cancellation tests and the existing stack-corruption live regression.

### F. Historical archive performs repeated global work — P1 on preview integration line

`HistoricalConsumptionArchiveStore.record` currently:

- selects leaders by repeatedly sorting useful applications for five selectors;
- scans and prunes all retained buckets on every recorded snapshot;
- compacts oversized bucket dictionaries with repeated full sorts;
- encodes the complete seven-day archive and atomically rewrites the entire JSON file once per minute.

The schema and atomic safety are sound, but disk and CPU cost scale with archive size.

Expected value: lower periodic CPU, allocations and disk writes while retaining seven-day correctness.  
Risk: high because schema migration, crash safety and ranking semantics must not regress.  
Complexity: high.  
Verification: generated seven-day archive benchmark, byte-for-byte semantic leader comparison, interruption/crash recovery tests, migration tests and disk-write counters.

### G. SwiftUI chart transformations repeat inside view evaluation — P2

Examples:

- `OverviewView.history` filters the complete CPU history and performs segmentation in the computed view property;
- `MetricDetailView` repeatedly filters histories and creates chart point arrays;
- supplemental network/storage charts filter, `flatMap`, recompute maxima and create new UUID-backed points during view evaluation;
- process rankings filter and sort during view evaluation;
- several row/byte/number formatting paths allocate formatter objects repeatedly.

Expected value: fewer transient arrays, UUID allocations, sorts and redraw work while windows are visible.  
Risk: medium because Chart identity and range behavior are user-visible.  
Complexity: medium.  
Verification: SwiftUI update/signpost counts, allocation comparison and fixed-axis UI tests for 5 min, 15 min and 1 h.

### H. Status-bar image is fully rasterized for every snapshot — P2 measurement-gated

Every snapshot causes `MenuBarStatusTitleRenderer.lightImage` to:

- format all selected metrics;
- resolve/copy symbol images;
- measure strings;
- allocate `NSBitmapImageRep` and graphics context;
- draw and recolor the complete bitmap;
- create a new non-template `NSImage`.

The renderer exists to preserve correct white glyphs in affected macOS appearances, so it must not be replaced casually. A safe optimization would first measure render duration and allocation volume, then consider deduplication when rendered segments are unchanged or caching static symbol masks/layout components.

Expected value: reduce AppKit allocations and main-thread work.  
Risk: high due to previously fixed light/dark rendering regressions.  
Complexity: medium.  
Verification: exact EN/RU value rendering, light/dark physical checks, percent-sign regression, image-pixel tests and allocation/time comparison.

## 7. Duplicate operations map

Confirmed duplicate or repeated work:

1. full history array materialization after every sample;
2. broad publication of unrelated histories to all coordinator observers;
3. front removal and shifting in every filled ring buffer;
4. repeated chart filtering and segmentation from already-published arrays;
5. per-window process providers plus the preview historical provider;
6. repeated running-application enumeration for process consumers/history;
7. repeated full JSON encoding and atomic replacement;
8. repeated ranking sorts during every historical record;
9. repeated status-bar bitmap allocation even when formatted segments may be unchanged;
10. formatter and application-icon lookup work inside SwiftUI row evaluation.

Potential duplicate work requiring measurement before confirmation:

- repeated IOKit registry traversal across battery, adapter and power telemetry providers;
- SMC reads that could safely share a connection or cadence across temperature/fan paths;
- multiple Settings/Combine invalidations caused by broad observable objects.

## 8. MainActor and concurrency risks

### Confirmed MainActor pressure

- all `MetricsCoordinator` history appends and publications occur on `MainActor`;
- SwiftUI observes the whole coordinator through `EnvironmentObject`;
- process-monitor running-application enumeration happens in a main-actor task before provider sampling;
- network/storage preview readers execute from main-actor monitor tasks;
- status-bar bitmap creation is explicitly main-actor/AppKit work;
- archive center updates revision and history metadata on main actor every recorded sample.

### Existing strengths

- core synchronous system sampling is isolated in `SystemSampler` actor;
- process provider is actor-isolated;
- archive persistence is actor-isolated;
- task cancellation paths exist for core, process, network, storage and history loops;
- sleep/wake discontinuity is explicitly represented;
- no `Task.detached` usage was identified in the audited paths.

### Required concurrency checks for future changes

- no sample may be published after cancellation;
- no duplicate core loop may survive restart;
- actor changes must not introduce non-Sendable AppKit values;
- process delta baselines must have exactly one owner;
- sleep/wake must reset CPU/SMC/provider baselines before the next snapshot;
- fan-control termination safety remains on the main application lifecycle path.

## 9. SwiftUI invalidation analysis

The coordinator exposes the latest snapshot plus many history arrays from one broad `ObservableObject`. Any publication can invalidate views that only need a small subset of state.

High-value design direction:

- publish one immutable live snapshot atomically;
- expose histories through narrower observable stores or on-demand immutable views;
- batch related history revisions into one publication;
- preserve stable point identity across chart refreshes;
- precompute only ranges currently observed by visible windows;
- keep formatters/static layout helpers reusable and non-observable.

This is not a recommendation to introduce a large actor/view-model hierarchy. The smallest acceptable change is the one that measurably reduces publications and allocations while preserving behavior.

## 10. History and storage analysis

### Current in-memory history

Strengths:

- bounded capacity;
- discontinuity markers prevent charts from connecting across sleep/wake gaps;
- one-hour intended retention;
- immutable `TimedPoint` values.

Problems:

- maximum capacity is allocated logically for every metric regardless of active interval;
- the policy exposes `historyCapacity(for:)`, but `MetricsCoordinator` initializes every core buffer to the fixed maximum 3,600;
- front removal is linear;
- every buffer is exported to a full array after every sample;
- per-sensor/per-fan dictionaries multiply copies and publications.

### Historical leaders preview

Strengths:

- explicit schema version;
- seven-day retention;
- five-minute buckets;
- atomic write;
- bounded candidate selection;
- network leaders correctly return empty rather than fabricated statistics.

Problems:

- full archive rewrite;
- full retention pruning each sample;
- repeated sorting for candidate selection/compaction;
- synchronous archive loading during actor initialization path;
- a second process-sampling lifecycle independent of live consumers.

Any format change requires schema versioning and migration. Until then, optimization should preserve JSON v1 semantics or introduce a separately versioned v2 with a tested migration path.

## 11. CPU, memory, disk and energy assessment

### CPU

Most likely current CPU contributors, in priority order for measurement:

1. process enumeration and per-process sampling;
2. fan/SMC reads at short intervals;
3. MainActor history copying/publication;
4. Charts transformation/rendering with open windows;
5. status-bar bitmap rasterization;
6. historical ranking/JSON encoding in preview builds.

### Memory and allocations

Most likely allocation sources:

- copied history arrays;
- Chart point arrays and generated UUIDs;
- status-bar bitmap/context/image objects;
- repeated sorted process/history arrays;
- complete JSON `Data` buffers;
- repeated formatter creation.

### Disk

The audited product base should perform no periodic live-history disk writes. The historical preview introduces one full atomic archive rewrite per minute. That behavior requires exact write-volume measurement with a mature seven-day synthetic archive before integration.

### Energy and wakeups

The architecture uses sleep-based tasks rather than busy loops, but the number of independent loops grows with visible windows and preview modules. Wakeup reduction should focus on consolidating process sampling and decoupling expensive provider cadence from UI cadence, after exact measurement.

## 12. Prioritized optimization backlog

| ID | Priority | Task | Impact | Risk | Complexity | Acceptance evidence |
|---|---|---|---|---|---|---|
| O-01 | P0 | Exact-head physical baseline and complete timing/signpost coverage | enables all decisions | low | medium | Release ARM64 metrics, Instruments, wakeups, provider timings, open/closed windows |
| O-02 | P1 | Replace shifting `RingBuffer` and batch/on-demand history publication | CPU, memory, MainActor, SwiftUI | medium/high | medium/high | append benchmark, allocations, publish counts, graph equivalence |
| O-03 | P1 | Centralize process sampling for all live/history consumers | CPU, wakeups, threads | high | high | one provider loop, multi-window test, ranking/history equivalence |
| O-04 | P1 | Introduce measurement-driven provider cadence tiers | SMC/IOKit calls, energy | high | high | call counts, freshness, power-source and sleep/wake tests |
| O-05 | P1 | Make historical archive aggregation/persistence incremental | CPU, allocations, disk | high | high | seven-day benchmark, migration/recovery and semantic equivalence |
| O-06 | P2 | Move chart transformations/formatters out of repeated body evaluation | allocations, UI responsiveness | medium | medium | SwiftUI update counts, chart identity and range tests |
| O-07 | P2 | Deduplicate/cache unchanged status-bar rendering components | MainActor allocations | high | medium | physical light/dark and pixel regressions plus timing evidence |
| O-08 | P2 | Apply interval-derived history capacities instead of fixed 3,600 everywhere | memory | medium | low/medium | capacity tests and peak RSS comparison |
| O-09 | P3 | Audit imports, access levels and dead code after performance waves | maintainability/binary | low | low | build size and compiler warning comparison |

## 13. Measurement plan

### Environment record

Every run must capture:

- exact source SHA and branch;
- Mac model, chip, memory and macOS build;
- power source and Low Power Mode state;
- screen/HUD/popover/detail-window state;
- configured battery/external sampling intervals;
- Release or Debug configuration;
- unsigned status;
- test duration and sample cadence.

### Scenarios

1. cold launch to first complete snapshot;
2. idle, popover closed, no detail windows;
3. overview open;
4. CPU detail open with process consumers;
5. CPU + memory + GPU detail windows open simultaneously;
6. historical leaders collection active;
7. network/storage detail active;
8. sleep for at least one minute, wake and recover;
9. switch battery to external power and back;
10. minimum interval and maximum interval;
11. 30-minute run for allocation/wakeup comparison;
12. six-hour stability run after structural optimization.

### Metrics

- launch time to first snapshot;
- mean/p95/peak process CPU;
- provider p50/p95/max latency and call count;
- sampling-cycle p50/p95/max;
- main-thread time;
- wakeups and timer firings;
- allocations and peak/live RSS;
- threads and active Swift tasks where observable;
- Combine publication counts;
- SwiftUI body/update counts for overview and charts;
- status-bar render count and duration;
- disk bytes/writes and archive size;
- process-provider sample count with one and several windows;
- sleep/wake recovery latency and discontinuity correctness.

### Comparison rule

Use repeated paired runs on the same physical machine and scenario. Do not accept a change based on a single noisy run. Record raw evidence and report median plus range or p95 as appropriate.

## 14. Definition of done by wave

### Wave A — measurement foundation

- exact-head Release ARM64 build succeeds on approved self-hosted runner;
- all current tests pass and count is recorded;
- provider timing coverage is complete;
- idle/open-window/sleep-wake baselines are committed;
- no product behavior changes.

### Wave B — history publication

- ring buffer append is amortized/O(1) without front shifts;
- history semantics and discontinuities are unchanged;
- publication count and MainActor time decrease measurably;
- 5 min, 15 min and 1 h charts pass fixed-domain tests;
- RSS/allocations do not regress.

### Wave C — process sampling consolidation

- exactly one process delta baseline exists per application process;
- live rankings and history consume the same snapshot stream;
- no duplicate loop appears with multiple windows;
- PID reuse and C-bridge regression tests pass;
- no network or storage per-app fabrication is introduced.

### Wave D — provider cadence

- cadence tiers are derived from measured cost/freshness requirements;
- power-source changes are reflected promptly;
- expensive SMC/IOKit call count decreases;
- UI freshness remains within documented bounds;
- sleep/wake and cancellation tests pass.

### Wave E — archive persistence

- seven-day leader results match the reference implementation;
- write volume and encoding time decrease measurably;
- atomic recovery and schema migration pass;
- archive retention never exceeds seven days;
- no private user data is added.

### Wave F — UI/AppKit refinement

- SwiftUI update/Chart transformation counts decrease;
- status-bar rendering remains correct in light/dark appearance;
- EN/RU and accessibility smoke pass;
- no visual redesign is introduced.

## 15. Mandatory regression matrix

Every optimization wave must preserve:

- Custom Preset metric set/order and persistence;
- standard presets not overwriting Custom;
- correct status-bar values and percent signs in light/dark appearance;
- separate battery/external intervals once the power-aware branch is integrated;
- automatic interval switching on power-source change;
- fixed 5 min, 15 min and 1 h chart X domains with empty future area;
- correct consumption leaders and maximum seven-day retention;
- no leaders tab for network/storage and no fabricated network app consumption;
- sleep/wake recovery and graph discontinuities;
- complete task cancellation on termination;
- automatic fan-mode restoration;
- unchanged SMC/RPM safety constraints;
- no private user data persistence;
- EN/RU localization and accessibility identifiers.

## 16. Audit decision

Do **not** begin a broad refactor.

The first implementation wave must be O-01 measurement foundation. Structural work may then proceed in small PRs, starting with O-02 and O-03 if exact-head evidence confirms the expected costs.

No benchmarks, builds or tests were executed by this documentation-only audit. No claims are made beyond source inspection, existing repository evidence and deterministic complexity analysis.