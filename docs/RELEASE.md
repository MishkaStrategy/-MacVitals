# Release Process

## Pull-request release candidate

Every pull request runs an Apple Silicon macOS workflow that must complete:

1. Deterministic application-icon materialization and validation.
2. XcodeGen project generation.
3. SwiftFormat lint.
4. Native Debug build with strict Swift 6 concurrency.
5. Unit tests, including provider-backed hardware smoke coverage.
6. English and Russian Preferences UI smoke tests covering all five tabs and stable accessibility identifiers.
7. Unsigned Release archive with a numeric marketing/build version.
8. ZIP and compressed DMG creation using system tools.
9. SHA-256 generation and verification for binaries and provenance files.
10. Bundle metadata verification, including bundle identifier, executable, version, application icon, category, localizations and `LSUIElement`.
11. Universal `arm64` and `x86_64` executable verification.
12. Independent signing/notarization classification and exact `BUILD_MANIFEST.json` / `BUILD_STATUS.txt` consistency checks.
13. Read-only DMG mount verification, Applications shortcut check and ZIP/DMG payload comparison, including the icon.
14. Packaged-app runtime smoke with CSV/JSON evidence and broad runaway guardrails.
15. Upload of the unsigned release candidate and diagnostic logs.
16. YAML/plist/shell/localization/icon/output-path validation and secret scanning.

The UI smoke runs before archive/DMG creation so a confirmed UI failure does not consume packaging and runtime-smoke runner time.

A separate `macos-15-intel` workflow must also complete:

1. Deterministic application-icon materialization and validation.
2. Native x86_64 Release build.
3. Executable architecture verification.
4. Native x86_64 unit/provider tests.
5. Native x86_64 packaged-app runtime smoke and evidence upload.

Hosted Intel evidence reduces architecture risk but does not replace physical Intel MacBook battery/adapter validation.

## Candidate contents

The verified CI candidate contains:

- `MacVitals-<version>.zip`;
- `MacVitals-<version>.dmg`;
- `SHA256SUMS.txt`;
- `BUILD_STATUS.txt`;
- `BUILD_MANIFEST.json`.

`BUILD_STATUS.txt` provides the human-readable signing/notarization classification. `BUILD_MANIFEST.json` provides the machine-readable version, build, commit, Xcode, bundle, minimum macOS, architecture and artifact provenance. The verifier rejects extra manifest keys, malformed commit metadata, host-specific paths, or disagreement between either file and the actual application bundle. The packaged `AppIcon.icns` must match the reviewed project-owned source byte for byte.

Current CI candidates are intentionally unsigned and not notarized. Runtime evidence is uploaded as a separate workflow artifact because it describes the runner and execution, not the distributable application itself.

## Output-path safety

Packaging and CI runtime scripts normalize their output paths and require them to be strict descendants of the repository root. Repository-root, parent-traversal, external and symlink-escape paths are rejected before destructive cleanup.

`DIST_DIR` is treated as a dedicated MacVitals artifact directory. Before packaging, the script performs a two-phase inspection:

1. if any unexpected file, symlink or directory is present, packaging stops without deleting anything;
2. only recognized older MacVitals ZIP/DMG and metadata artifacts are removed before the new candidate is created.

This prevents an incorrect environment variable from deleting arbitrary user data and prevents unrelated files from being included in a workflow release artifact. `BUILD_DIR`, `DIST_DIR` and `CI_RUNTIME_OUTPUT_ROOT` may be relative, but they are resolved relative to the repository root.

Runtime collection durations are positive whole seconds. Concurrent direct collectors include their process ID in the evidence directory name to avoid same-second collisions.

## Publication safety

The tag-triggered **Release Candidate** workflow has read-only repository permissions. It builds, tests, verifies, runtime-smokes and uploads an unsigned workflow artifact for internal validation, but it intentionally cannot create a public GitHub Release.

A public release workflow must not be enabled until it can:

1. Import a Developer ID Application certificate from encrypted repository secrets.
2. Build and sign the application with Hardened Runtime.
3. Verify the code signature and designated requirement.
4. Submit the signed archive to Apple notarization.
5. Wait for a successful notarization result and retain its log.
6. Staple and validate the notarization ticket.
7. Run Gatekeeper assessment against the final app and DMG.
8. Recalculate provenance and checksums after all signing and stapling operations.
9. Publish only the exact verified signed artifacts.

## Final release gates

Before creating `v1.0.0`:

1. Run both the ARM PR workflow and Intel Compatibility workflow on the intended release commit.
2. Complete physical Apple Silicon laptop validation under battery and adapter transitions.
3. Complete physical Intel Mac validation for any retained Intel sensor claims, or explicitly narrow those claims.
4. Capture real screenshots and complete VoiceOver and visual accessibility review.
5. Record physical-device performance and Instruments measurements.
6. Complete a multi-hour stability run.
7. Review sensor compatibility and known limitations.
8. Obtain Apple Developer ID credentials.
9. Implement the secret-backed signed publication workflow described above.
10. Verify the stapled notarization ticket and Gatekeeper assessment on a clean Mac.
11. Merge only after required checks and audits pass.
12. Create the release tag only after the signed publication workflow is enabled and independently reviewed.

Never describe an unsigned CI artifact as signed, notarized or ready for frictionless Gatekeeper installation.
