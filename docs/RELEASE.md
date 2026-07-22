# Release Process

## Pull-request release candidate

Every pull request runs on a macOS ARM runner and must complete:

1. XcodeGen project generation.
2. SwiftFormat lint.
3. Native Debug build with strict Swift 6 concurrency.
4. Unit tests, including provider-backed hardware smoke coverage.
5. Unsigned Release archive with a numeric marketing/build version.
6. ZIP and compressed DMG creation using system tools.
7. SHA-256 generation and verification.
8. Bundle metadata verification, including bundle identifier, executable, version, category and `LSUIElement`.
9. Read-only DMG mount verification and Applications shortcut check.
10. Upload of the unsigned release candidate and diagnostic logs.
11. UI smoke test for the Preferences window and accessibility identifiers.
12. YAML/plist/shell validation and secret scanning.

The verified CI fallback produces:

- `MacVitals-<version>.zip`
- `MacVitals-<version>.dmg`
- `SHA256SUMS.txt`
- `BUILD_STATUS.txt`

`BUILD_STATUS.txt` is authoritative for signing and notarization status. Current CI candidates are explicitly unsigned and not notarized.

## Final release gates

Before creating `v1.0.0`:

1. Run the full PR workflow on the intended release commit.
2. Complete physical Apple Silicon laptop validation under battery and adapter transitions.
3. Complete Intel Mac validation or explicitly narrow the supported hardware claim.
4. Capture real screenshots and accessibility evidence.
5. Record physical-device performance measurements.
6. Review sensor compatibility and known limitations.
7. Obtain Apple Developer ID credentials.
8. Add repository-secret-backed signing and notarization without hard-coded credentials.
9. Verify the stapled notarization ticket and Gatekeeper assessment on a clean Mac.
10. Merge only after required checks and audits pass.
11. Create tag `v1.0.0`; the release workflow publishes only files that passed packaging verification.

Never describe an unsigned CI artifact as signed, notarized or ready for frictionless Gatekeeper installation.
