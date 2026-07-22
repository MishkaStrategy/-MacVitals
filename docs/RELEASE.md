# Release Process

1. Run the PR workflow on a macOS runner.
2. Capture real screenshots and performance evidence.
3. Verify unit/UI/hardware tests and update compatibility documentation.
4. Merge `feature/macvitals-v1` only after required checks pass.
5. Create tag `v1.0.0`.
6. The release workflow produces ZIP, optional DMG, SHA-256 and an explicit signing status.
7. With no Apple credentials, artifacts are unsigned and non-notarized. Never describe them otherwise.
8. With credentials, add documented codesign/notarization steps using repository secrets; never hard-code credentials.
