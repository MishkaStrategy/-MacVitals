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

## Publication safety

The tag-triggered **Release Candidate** workflow has read-only repository permissions. It builds, verifies and uploads an unsigned workflow artifact for internal validation, but it intentionally cannot create a public GitHub Release.

A public release workflow must not be enabled until it can:

1. Import a Developer ID Application certificate from encrypted repository secrets.
2. Build and sign the application with Hardened Runtime.
3. Verify the code signature and designated requirement.
4. Submit the signed archive to Apple notarization.
5. Wait for a successful notarization result and retain its log.
6. Staple and validate the notarization ticket.
7. Run Gatekeeper assessment against the final app and DMG.
8. Recalculate checksums after all signing and stapling operations.
9. Publish only the exact verified signed artifacts.

## Final release gates

Before creating `v1.0.0`:

1. Run the full PR workflow on the intended release commit.
2. Complete physical Apple Silicon laptop validation under battery and adapter transitions.
3. Complete Intel Mac validation or explicitly narrow the supported hardware claim.
4. Capture real screenshots and accessibility evidence.
5. Record physical-device performance measurements.
6. Review sensor compatibility and known limitations.
7. Obtain Apple Developer ID credentials.
8. Implement the secret-backed signed publication workflow described above.
9. Verify the stapled notarization ticket and Gatekeeper assessment on a clean Mac.
10. Merge only after required checks and audits pass.
11. Create the release tag only after the signed publication workflow is enabled and independently reviewed.

Never describe an unsigned CI artifact as signed, notarized or ready for frictionless Gatekeeper installation.
