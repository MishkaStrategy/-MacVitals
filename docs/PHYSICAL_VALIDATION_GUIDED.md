# Guided Physical Apple Silicon Validation

This guide runs the existing conservative physical-validation harness through an interactive menu. It does not weaken acceptance criteria and cannot mark a scenario or manual gate as passed automatically.

The flow supports native Apple Silicon (`arm64`) only. Intel and universal validation remain outside the MacVitals v1 scope.

## 1. Prepare the repository

Check out the exact reviewed feature commit or, after merge, the exact reviewed `main` commit. Do not use a moving unverified checkout.

From the repository root, place the five files from the intended `MacVitals-<version>-arm64-unsigned` workflow artifact directly in `dist/`:

- `MacVitals-<version>.zip`;
- `MacVitals-<version>.dmg`;
- `BUILD_STATUS.txt`;
- `BUILD_MANIFEST.json`;
- `SHA256SUMS.txt`.

With GitHub CLI, a typical download command is:

```bash
rm -rf dist
mkdir dist
gh run download <workflow-run-id> \
  --name MacVitals-<version>-arm64-unsigned \
  --dir dist
```

The guide rejects missing, extra, empty or symlinked candidate entries. `dist/` must contain exactly the five intended files.

## 2. Start the guided flow

Run:

```bash
python3 scripts/run_physical_validation_guided.py start --dist dist
```

The guide:

1. requires a native arm64 Mac;
2. reads the candidate version, build, commit and architecture;
3. requires the exact five-file candidate scope;
4. runs the complete release verifier **before** extracting the ZIP;
5. extracts the verified ZIP into a new ignored directory below `physical-validation-apps/`;
6. verifies that the extracted app executable exactly matches the candidate ZIP;
7. creates a new session below `physical-validation-results/`;
8. opens the interactive menu.

Existing extracted-app or session directories are never silently reused. Candidate, session and extracted-app inputs cannot escape the repository through symlinks.

## 3. Use the menu

The menu offers:

- run a physical scenario;
- record a separate human scenario review;
- record a manual or Instruments gate;
- show current status;
- finalize the acceptance record;
- exit.

Scenario profiles use the project-approved defaults:

| Scenario | Duration | Interval |
|---|---:|---:|
| battery-idle | 15 minutes | 2 seconds |
| external-power-idle | 15 minutes | 2 seconds |
| adapter-transition | 5 minutes | 2 seconds |
| sleep-wake | 5 minutes | 2 seconds |
| popover-closed | 15 minutes | 2 seconds |
| popover-open | 15 minutes | 2 seconds |
| high-frequency | 15 minutes | 0.5 seconds |
| stress | 15 minutes | 2 seconds |
| stability-six-hour | 6 hours | 2 seconds |
| batteryless-desktop | 15 minutes | 2 seconds |

Before each run, the guide prints the required physical action and requires typing `RUN`. Every collected scenario remains `pending-review` until a human records `pass`, `fail`, `not-tested` or `unsupported` separately.

The `independentReviewer` gate must be recorded only by a separate reviewer. Signing, notarization, stapling and clean-Mac Gatekeeper gates must remain `not-tested` until the final signed candidate exists.

## 4. Resume later

The start command prints the session path. Resume it with:

```bash
python3 scripts/run_physical_validation_guided.py resume \
  --session physical-validation-results/session-<UTC>-<PID>
```

The guide uses the exact extracted application recorded in `guided-session.json`; it does not accept a replacement application during resume. The low-level harness rechecks the executable SHA-256 before every scenario.

## 5. Finalize conservatively

Choose **Finalize acceptance record** from the menu, or use the low-level command documented in [`PHYSICAL_VALIDATION_RUNBOOK.md`](PHYSICAL_VALIDATION_RUNBOOK.md).

An incomplete result and exit status `2` are expected while any required scenario or manual gate remains open. Do not delete open items or edit generated runtime evidence to force completion.

## Privacy and evidence handling

The harness redacts home paths and rejects generated text evidence containing `/Users/<name>` or `/home/<name>`. It does not record a serial number, Apple ID or user documents.

Before attaching evidence to the PR:

1. inspect the complete session locally;
2. keep Instruments trace binaries separate;
3. attach or commit only redacted evidence approved by the project reviewer;
4. never upload certificate material, notary keys or unrelated user files.
