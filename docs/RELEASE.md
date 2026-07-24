# Release Process

## Pull-request release candidate

Every pull request runs an Apple Silicon macOS workflow that must complete:

1. Deterministic application-icon materialization and validation.
2. XcodeGen project generation with `arm64` as the only supported architecture.
3. SwiftFormat lint.
4. Native arm64 Debug build with strict Swift 6 concurrency.
5. Native arm64 unit tests, including provider-backed hardware smoke coverage.
6. English and Russian Preferences UI smoke tests covering all five tabs and stable accessibility identifiers.
7. Unsigned arm64 Release archive with a numeric marketing/build version.
8. ZIP and compressed DMG creation using system tools.
9. SHA-256 generation and verification for binaries and provenance files.
10. Bundle metadata verification, including bundle identifier, executable, version, application icon, category, localizations and `LSUIElement`.
11. Exact arm64-only executable verification. Universal and x86_64 binaries are rejected.
12. Independent signing/notarization classification and exact `BUILD_MANIFEST.json` / `BUILD_STATUS.txt` consistency checks.
13. Read-only DMG mount verification, Applications shortcut check and ZIP/DMG payload comparison, including the icon.
14. Packaged-app runtime smoke with schema-v3 CSV/JSON evidence, monotonic timing, stable process identity, PID-reuse detection, privacy scanning and broad runaway guardrails on hosted Apple Silicon macOS.
15. Hosted preparation smoke for the exact physical-validation candidate without claiming physical evidence.
16. Deterministic self-tests for the private Developer ID signing/notarization pipeline and its path-isolation entrypoint without using real credentials.
17. Upload of the unsigned arm64 release candidate and diagnostic logs.
18. YAML/plist/shell/localization/icon/output-path validation and secret scanning.

The UI smoke runs before archive/DMG creation so a confirmed UI failure does not consume packaging and runtime-smoke runner time.

Intel compatibility is outside the supported product scope. There is no Intel workflow, and release verification must fail if the packaged executable contains `x86_64` or any architecture other than `arm64`.

## Candidate contents

The verified CI candidate contains:

- `MacVitals-<version>.zip`;
- `MacVitals-<version>.dmg`;
- `SHA256SUMS.txt`;
- `BUILD_STATUS.txt`;
- `BUILD_MANIFEST.json`.

`BUILD_STATUS.txt` provides the human-readable signing/notarization classification. `BUILD_MANIFEST.json` provides the machine-readable version, build, commit, Xcode, bundle, minimum macOS, architecture and artifact provenance. The verifier rejects extra manifest keys, malformed commit metadata, host-specific paths, disagreement between either file and the actual application bundle, or any packaged architecture other than `arm64`. The packaged `AppIcon.icns` must match the reviewed project-owned source byte for byte.

Normal PR/main/tag-validation candidates are intentionally unsigned and not notarized. Runtime evidence is uploaded as a separate workflow artifact because it describes the runner and execution, not the distributable application itself. Runtime CSV, JSON and logs must not contain usernames or user home paths.

## Output-path safety

Packaging and CI runtime scripts normalize their output paths and require them to be strict descendants of the repository root. Repository-root, parent-traversal, external and symlink-escape paths are rejected. Packaging additionally requires `BUILD_DIR` and `DIST_DIR` to be non-overlapping.

`DIST_DIR` is treated as a dedicated MacVitals artifact directory. Before packaging, the script performs a two-phase inspection:

1. if any unexpected file, symlink or directory is present, packaging stops without deleting anything;
2. only recognized older MacVitals ZIP/DMG and metadata artifacts are removed before the new candidate is created.

This prevents an incorrect environment variable from deleting arbitrary user data and prevents unrelated files from being included in a workflow release artifact. `BUILD_DIR`, `DIST_DIR` and `CI_RUNTIME_OUTPUT_ROOT` may be relative, but they are resolved relative to the repository root.

Runtime smoke does not delete its output base. Each invocation creates a unique `run-<UTC>-<PID>` directory. An existing output base is accepted only when every entry is a previous non-symlink run directory with that exact naming contract; source-like or contaminated directories are rejected before the application launches. This preserves prior evidence and prevents `CI_RUNTIME_OUTPUT_ROOT` from erasing source or build data.

Runtime collection durations are positive whole seconds. Direct collectors include their process ID in the evidence directory name to avoid same-second collisions. Console output omits or redacts the user home directory, and the runtime smoke fails when generated evidence contains `/Users/<name>` or `/home/<name>` paths.

Private signed outputs use separate `signed-dist/`, `signed-release-work/` and `signed-release-evidence/` roots. `scripts/signed_release_entrypoint.py` resolves all three paths before credentials are used and rejects equality, parent/child nesting, repository-root paths, external paths and symlink escapes. Each successful candidate is bound to version, build number and exact commit SHA. Existing output directories are never silently reused.

## Publication safety

The tag-triggered **Release Candidate** workflow has read-only repository permissions. It builds, tests, verifies, runtime-smokes and uploads an unsigned arm64 workflow artifact for internal validation, but it intentionally cannot create a public GitHub Release.

The manual **Signed Release Candidate** workflow routes through `scripts/signed_release_entrypoint.py` and then `scripts/sign_notarize_release.py` to create a private Developer ID candidate. They:

1. require the exact authorization phrase and immutable commit SHA;
2. prove that signed output, work and evidence roots are mutually non-overlapping strict repository children before importing credentials;
3. use the protected `signed-release` environment;
4. import certificate/API-key material into temporary runner files and a temporary keychain;
5. sign the app with Developer ID, Hardened Runtime and a trusted timestamp;
6. submit the application ZIP to Apple notarization and retain its response/log;
7. staple and validate the application ticket;
8. create and Developer ID sign the final DMG;
9. submit the DMG separately to notarization and retain its response/log;
10. staple and validate the DMG ticket;
11. run Gatekeeper assessment against both app and DMG;
12. regenerate provenance and checksums only after signing/stapling;
13. rerun the full release verifier against the exact requested commit;
14. upload private workflow artifacts with `contents: read` permissions;
15. delete temporary signing material in an unconditional cleanup step;
16. explicitly record that no public GitHub Release was created.

Follow [`SIGNED_RELEASE_RUNBOOK.md`](SIGNED_RELEASE_RUNBOOK.md). The workflow must not gain tag triggers, `contents: write` or a release-publication action.

A future public-release action must remain disabled until it can publish only an independently reviewed, clean-Mac-validated artifact after separate user authorization.

## Final release gates

Before creating `v1.0.0`:

1. Run the ARM pull-request workflow on the intended release commit.
2. Complete physical Apple Silicon laptop validation under battery and adapter transitions.
3. Validate graceful unsupported battery behavior on at least one battery-less Apple Silicon Mac when available.
4. Capture real screenshots and complete VoiceOver and visual accessibility review.
5. Record physical-device performance and Instruments measurements.
6. Complete a multi-hour stability run.
7. Review sensor compatibility and known limitations for the Apple Silicon-only scope.
8. Obtain Apple Developer ID credentials and configure the protected `signed-release` environment.
9. Run and independently inspect the private signed/notarized candidate workflow.
10. Verify the stapled notarization tickets and Gatekeeper assessments on a clean Apple Silicon Mac.
11. Complete the separate independent audit.
12. Merge only after required checks and audits pass and after explicit user authorization.
13. Create the release tag and public GitHub Release only after separate explicit publication authorization.

Never describe an unsigned CI artifact as signed, notarized or ready for frictionless Gatekeeper installation. A private signed workflow artifact is also not a public release.
