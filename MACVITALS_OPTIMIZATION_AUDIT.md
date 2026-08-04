# MacVitals Optimization Audit — Post-Notch Canonical Baseline

Status: **baseline reset complete; optimization implementation not started**  
Tracking issue: #48  
Baseline issue: #49  
Audit branch: `audit/macvitals-optimization-post-notch`  
Canonical product branch: `feature/macvitals-v1`  
Exact canonical product source SHA: `4d143aaa082b0fb15ce86d19ba72c40557939692`

## 1. Why this audit replaces the previous audit

The previous audit branch and PR #55 were based on product SHA:

`fe97c56e458b3a9dc67cab8451737bc6945703f5`

That SHA predates the accepted pre-pet contour HUD. Any build, benchmark or physical test inherited from that branch can legitimately launch the old tile-based interface even though the current product contract has already moved forward.

PR #55 was therefore closed without merge. It is historical evidence only and must not be used as an optimization base.

This document starts again from the accepted product integration:

`4d143aaa082b0fb15ce86d19ba72c40557939692`

Every future optimization branch, artifact and physical test must be this SHA or a documented descendant of it.

## 2. Canonical UI and runtime contract

Optimization is allowed to improve implementation cost, but it must preserve the accepted product behavior.

### Notch HUD

The canonical HUD is the version accepted before the pet experiment:

- one transparent central AppKit `NSPanel`;
- one U-shaped contour around the physical display cutout;
- hardware bounds resolved from `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea`;
- visible inner stroke edge aligned to the hardware safe-area boundary;
- no artificial four-point gap;
- one or two independent indicator segments;
- labels can be enabled or disabled;
- no old left/right tile panels;
- no pet or mascot code from closed PR #41.

Reference physical validation for the accepted exact candidate:

- exact product candidate: `2d1fbd0342689af1629e2ee9875e5e5238f37ea2`;
- self-hosted ARM64 CI run: `30885053577` — success;
- exact-head physical run: `30885328356` — success;
- screen: `2056×1329`;
- `safeAreaTop = 38`;
- physical notch width: `220 pt`;
- physical notch center X: `1028 pt`;
- overlay frame: `x = 846`, width `364 pt`;
- exactly one visible AppKit panel;
- single/dual and labels/no-labels profiles passed;
- 30-second runtime passed;
- preferences were restored.

The final stacked merge was validated again on head `68abc989f22dfe62f2479ec7c0d8e5c9237b3a46` before merge into the canonical product branch.

### Other protected behavior

Optimization must also preserve:

- correct white status-bar values and `%` sign in supported appearances;
- Custom Preset persistence and ordering;
- separate sampling intervals for battery and external power where integrated;
- automatic power-source interval switching;
- fixed graph X ranges for 5 min, 15 min and 1 h;
- explicit gaps across sleep/wake discontinuities;
- no per-app network consumption fabrication;
- no consumption-leader tab for Network and Storage;
- seven-day historical-consumption retention where that feature is integrated;
- EN/RU localization and accessibility identifiers;
- fan safety, automatic restoration on termination and no unsafe SMC writes.

## 3. Mandatory source and artifact gate

Before any build, benchmark or physical launch:

1. Resolve the current canonical product head.
2. Record the exact source SHA.
3. Verify that the candidate is `4d143aaa…` or a descendant.
4. Verify artifact metadata `head_sha` and branch.
5. Reject artifacts from:
   - `fe97c56e…`;
   - old tile HUD branches;
   - pet branches;
   - stale preview/validation branches not rebased onto the canonical product line;
   - GitHub-hosted macOS jobs.
6. For physical HUD tests, assert source markers for:
   - `hardwareNotchGeometry`;
   - auxiliary top-area resolution;
   - one central panel;
   - zero artificial contour clearance.

A successful test of the wrong source is a failed validation.

## 4. Approved CI policy

All new MacVitals work must use:

`[self-hosted, macOS, ARM64]`

The accepted PR workflow currently provides:

- Swift format lint;
- ARM64 build;
- ARM64 unit tests;
- unsigned release packaging and verification;
- UI-test target build plus EN/RU localization/accessibility validation;
- repository safety and Gitleaks;
- downloaded-artifact staging smoke;
- packaged runtime smoke.

Executable XCUITest is not used as the generic CI gate on these self-hosted machines because the local XCTest Runner can conflict with installed Team IDs. Actual GUI behavior is verified by a separate exact-artifact physical harness.

## 5. Architecture map

### Application lifecycle

`MacVitals/App/AppDelegate.swift`

- constructs settings, coordinator, fan client and notification components;
- starts the system sampling lifecycle;
- connects snapshot publication to the status item and HUD;
- stops tasks and restores automatic fan behavior during termination.

### Core metrics

`MacVitals/Monitoring/SystemSampler.swift`

- actor-isolated provider coordinator;
- samples CPU, memory, battery, adapter, direct power, GPU, temperature and fan state;
- produces an immutable `SystemSnapshot` and timing data.

`MacVitals/Monitoring/MetricsCoordinator.swift`

- MainActor observable owner of the live snapshot;
- owns the core sampling task;
- stores and publishes short-term histories;
- handles sleep/wake discontinuity semantics.

### AppKit and SwiftUI boundary

- `StatusItemController` owns status-item rendering, popover lifecycle and notch-HUD updates;
- `NotchHUDController` owns one nonactivating panel and resolves physical notch geometry;
- overview and detail SwiftUI trees observe broad coordinator/settings objects;
- detail windows and process consumers may introduce additional tasks and transformations.

### Persistence and previews

- settings use `UserDefaults`;
- core short-term histories are memory-backed;
- historical-consumption work, where integrated, uses five-minute buckets and a seven-day local archive;
- network and storage monitors use separate shared monitor lifecycles on their preview/integration lines.

## 6. Sampling and task map

| Area | Owner | Current cost/risk to measure |
|---|---|---|
| Core system sample | `MetricsCoordinator` + `SystemSampler` | all providers can share a user-visible cadence even when costs differ |
| Temperature | temperature provider | SMC reads and cache cadence |
| Fans | fan provider | repeated SMC key reads at fast intervals |
| Status item | `StatusItemController` | full bitmap creation on snapshot/settings changes |
| Notch HUD | `NotchHUDController` and SwiftUI content | reading/shape recomputation and AppKit updates |
| Short histories | `MetricsCoordinator` | array copies and broad publication on MainActor |
| Detail processes | `ProcessConsumersMonitor` | independent providers/tasks per window |
| Historical processes | historical center integration line | potential duplicate process sampling |
| Network/storage | shared monitor integration lines | separate loops and history transformations |
| Archive persistence | historical archive store | sorting, compaction, full JSON encode/write |
| Sleep/wake | lifecycle monitor | cancellation, baseline reset and discontinuity publication |

## 7. Confirmed optimization backlog

### O-01 — exact merged-head physical baseline and timing coverage — P0

Tracking: #49

Measure the current accepted product before changing cadence or architecture.

Required evidence:

- exact source SHA and ancestry;
- closed popover idle;
- open overview;
- accepted notch HUD enabled;
- several detail windows;
- sleep/wake;
- battery/external-power transitions;
- provider call counts and p50/p95/max latency;
- total sample-cycle time;
- MainActor publication time;
- status bitmap render count/time;
- notch-HUD update count/time;
- allocations, RSS, threads and wakeups where supported.

No optimization implementation begins before this baseline unless the change has deterministic structural proof and regression tests.

### O-02 — true circular history storage and reduced publication fan-out — P1

Tracking: #50

Confirmed opportunities:

- remove `Array.removeFirst()` shifting after capacity is reached;
- avoid materializing every complete history array every sample;
- narrow publication to visible/consuming views where safe;
- preserve ordering, timestamps and discontinuity semantics.

### O-03 — centralized process sampling — P1

Tracking: #51

Confirmed opportunity:

- eliminate duplicate running-application enumeration and process counter reads across multiple detail windows and historical aggregation;
- preserve one owner for delta baselines, PID reuse protection and cancellation.

The ProcessMetricsProvider safety fix and its live regression are protected.

### O-04 — measurement-driven provider cadence tiers — P1

Tracking: #53

Potentially expensive SMC/IOKit providers should not automatically run at the fastest UI cadence. The exact tiering policy must be derived from O-01 evidence, not guessed.

Must preserve:

- freshness timestamps;
- power-source transitions;
- sleep/wake reset;
- fan and thermal safety display;
- status item and notch-HUD freshness.

### O-05 — incremental historical aggregation and persistence — P1

Tracking: #52

Only after the historical feature is integrated onto a descendant of `4d143aaa…`:

- reduce repeated leader sorts;
- avoid full retained-bucket scans every snapshot;
- reduce full archive encoding and disk bytes;
- preserve seven-day semantics, schema migration and atomic recovery.

### O-06 — chart transformation and identity optimization — P2

Tracking: #54

Measure and reduce:

- repeated history filtering/segmentation in view evaluation;
- transient arrays and UUID-backed chart points;
- repeated maxima calculations and formatter allocations;
- broad SwiftUI invalidation.

Fixed X domains and sleep/wake gaps are mandatory regressions.

### O-07 — status-item and notch-HUD render deduplication — P2

Tracking: #54

Measure first, then skip only provably unchanged output.

Do not replace:

- the non-template white bitmap behavior;
- physical notch geometry resolution;
- one-panel HUD lifecycle;
- single/dual and labels behavior.

### O-08 — cancellation and lifecycle audit — P2

Cross-cutting verification:

- no sample publishes after cancellation;
- no duplicate loop survives restart;
- no stale provider result is presented as current;
- termination restores safe fan state;
- sleep/wake inserts one intentional discontinuity and resets baselines.

### O-09 — dead code and build graph cleanup — P3

Only after active integration branches are classified:

- identify unreachable legacy tile HUD code;
- remove obsolete validation workflows after retaining evidence references;
- avoid broad formatting or file movement that obscures performance diffs.

No old branch is deleted merely because it is not canonical; evidence branches may remain historical.

## 8. Measurement rules

An optimization is accepted only when at least one result is demonstrated:

- lower CPU;
- fewer wakeups or expensive provider calls;
- lower MainActor duration;
- fewer allocations/copies;
- lower RSS or thread count;
- lower disk bytes/writes;
- lower render/update counts;
- eliminated data race, leak, duplicate loop or deterministic O(n) operation;
- simpler architecture with unchanged observable behavior and strong tests.

Every comparison records:

- base SHA;
- candidate SHA;
- hardware and macOS version;
- sampling settings and power source;
- scenario duration;
- app state and visible windows;
- raw evidence location;
- unsupported metrics and limitations.

## 9. Mandatory regression matrix

Every optimization PR runs the relevant subset and the final integration runs all applicable gates:

- ARM64 build and unit tests;
- UI-test target build and EN/RU localization validation;
- repository safety and Gitleaks;
- package and runtime smoke;
- Custom Preset persistence;
- battery/external sampling settings;
- graph fixed ranges and discontinuities;
- status values and `%` rendering;
- no network/storage per-app leaders;
- historical retention/schema tests where integrated;
- exact source ancestry;
- physical accepted pre-pet HUD test when AppKit/SwiftUI/status/sampling changes can affect it.

Physical HUD acceptance requires:

- one central panel;
- no legacy side tiles;
- no pet;
- actual hardware width/center resolution;
- visible contour edge aligned to safe area;
- single/dual and labels on/off;
- preferences restored;
- no desktop capture.

## 10. Work order

1. Complete #49 exact merged-head baseline.
2. Select the first measured P1 optimization.
3. Create one branch from `4d143aaa…` or the latest accepted optimization head.
4. Implement one logical change.
5. Run exact self-hosted ARM64 tests and measurements.
6. Run physical HUD regression if the change can affect rendering, timing or lifecycle.
7. Open a Draft PR with before/after evidence.
8. Do not merge without explicit owner decision.

The first implementation target will be chosen only after #49 produces a trustworthy exact-head baseline.
