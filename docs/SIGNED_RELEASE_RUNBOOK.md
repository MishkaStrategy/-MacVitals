# Private Signed Release Candidate Runbook

This runbook creates a **private** Developer ID signed and notarized MacVitals candidate from an immutable commit already merged into `main`. It does not create a tag or publish a GitHub Release.

The signed pipeline supports Apple Silicon (`arm64`) only. Intel and universal artifacts remain unsupported and are verification failures.

## Workflow availability

GitHub exposes a `workflow_dispatch` workflow only after its YAML exists on the default branch. Therefore `.github/workflows/signed-release-candidate.yml` is intentionally a post-merge gate. Complete physical/manual validation and independent PR review first, merge only with explicit user authorization, and then sign the exact merge commit from `main`.

A signing failure after merge must be fixed through a new reviewed pull request. Never replace or silently mutate failed evidence.

## Safety contract

The workflow `.github/workflows/signed-release-candidate.yml`:

- runs only through `workflow_dispatch`;
- requires the exact authorization phrase `SIGN_MACVITALS_RELEASE_CANDIDATE`;
- checks out an explicitly supplied 40-character commit SHA;
- verifies that the commit is present on `origin/main` before signing material is used;
- uses the protected `signed-release` GitHub environment;
- has read-only repository permissions;
- routes all credential-backed execution through `scripts/signed_release_entrypoint_hardened.py`, which launches `scripts/sign_notarize_release_hardened.py` in the isolated subprocess boundary;
- preserves and revalidates the exact supported XcodeGen provenance (`2.45.4` or `2.46.0`) from unsigned archive through signed manifest;
- rejects equal, nested, external, repository-root and symlink-escape output/work/evidence paths before signing material is used;
- imports the Developer ID certificate into a temporary keychain;
- deletes the temporary keychain, certificate and notary API key file in an `always()` cleanup step;
- creates workflow artifacts only;
- cannot create a public GitHub Release.

Do not add a tag trigger, `contents: write`, release-creation action or automatic publication step to this workflow.

## Required Apple material

Prepare these values outside the repository:

1. A valid **Developer ID Application** certificate exported as a password-protected PKCS#12 (`.p12`) file.
2. The exact certificate display name, for example `Developer ID Application: Example Company (ABCDEFGHIJ)`.
3. The ten-character Apple Developer Team ID.
4. An App Store Connect API key (`AuthKey_<KEY_ID>.p8`) with permission to submit notarization requests.
5. The ten-character API key ID.
6. The API issuer UUID.

Never commit the certificate, password, API key or their encoded values.

## Protected environment

Create a GitHub environment named `signed-release` and configure required reviewers before adding secrets. Restrict deployment branches to `main` under the repository policy.

Store the following as environment secrets:

| Secret | Content |
|---|---|
| `MACVITALS_DEVELOPER_ID_P12_BASE64` | Base64 of the complete `.p12` file |
| `MACVITALS_DEVELOPER_ID_P12_PASSWORD` | Password used when exporting the `.p12` |
| `MACVITALS_DEVELOPER_ID_APPLICATION` | Exact Developer ID Application identity string |
| `MACVITALS_DEVELOPER_TEAM_ID` | Ten-character Team ID |
| `MACVITALS_NOTARY_API_KEY_P8_BASE64` | Base64 of the complete `.p8` API key |
| `MACVITALS_NOTARY_KEY_ID` | Ten-character API key ID |
| `MACVITALS_NOTARY_ISSUER_ID` | API issuer UUID |

Generate base64 locally without copying secret material into shell history. Confirm the resulting secret is not line-wrapped or truncated. Delete temporary encoded files after the GitHub secret has been verified.

## Pre-run release gates

Before authorizing a private signed candidate:

1. Confirm the intended commit is already present on `main` in `mishkacher/-MacVitals`.
2. Confirm the merge commit's Main workflow is completely green.
3. Confirm the corresponding PR head passed the unsigned arm64 package verifier and hosted runtime/privacy gates.
4. Confirm physical Apple Silicon, manual accessibility/visual and independent PR review gates were completed before merge.
5. Record the exact `main` commit SHA in the release checkpoint.
6. Obtain explicit user authorization for a private signed candidate.

Do not sign an unreviewed moving branch name. Always sign an immutable SHA already reachable from `origin/main`.

## Manual workflow invocation

Open **Actions → Signed Release Candidate → Run workflow** and supply:

- `version`: the intended numeric version, such as `1.0.0`;
- `expected_commit`: the exact lowercase 40-character `main` commit SHA;
- `authorization`: `SIGN_MACVITALS_RELEASE_CANDIDATE`.

The workflow checks out that SHA directly and verifies that it is contained in `origin/main`. A mismatch or unmerged commit is a hard failure before signing material is used.

## Pipeline stages

The workflow, `scripts/signed_release_entrypoint_hardened.py` and `scripts/sign_notarize_release_hardened.py` perform:

1. Exact checkout and `origin/main` ancestry verification.
2. Python compilation and deterministic self-tests, including adversarial path-isolation and provenance cases.
3. Resolution of signed output, work and evidence roots; all three must be mutually non-overlapping strict repository children with no symlink escape.
4. Verification that the installed XcodeGen is one of the empirically validated versions (`2.45.4` or `2.46.0`).
5. SwiftFormat lint and native arm64 unit tests.
6. Temporary keychain creation and Developer ID certificate import.
7. A fresh unsigned arm64 archive through the existing package/release verifier.
8. Exact manifest, version, build, commit, architecture and XcodeGen provenance validation.
9. Developer ID Application signing with Hardened Runtime, trusted timestamp and project entitlements.
10. Strict app signature, authority, Team ID, timestamp and arm64 verification.
11. Application ZIP submission to Apple notarization with `--wait`.
12. Retention of the application submission response and notarization log.
13. Stapling and validation of the application ticket.
14. Creation of the final ZIP and DMG from the stapled application.
15. Developer ID signing and verification of the DMG.
16. DMG submission to Apple notarization with `--wait`.
17. Retention of the DMG submission response and notarization log.
18. Stapling and validation of the DMG ticket.
19. Gatekeeper assessment of both the application and DMG.
20. Regeneration of signed/notarized provenance and SHA-256 files after stapling while preserving the original supported XcodeGen version.
21. Full `verify_release.sh` validation against the exact requested commit, including structural/resource/CRC validation of the final signed application ZIP before extraction.
22. Privacy scanning of text evidence and metadata.
23. Upload of private candidate and evidence workflow artifacts.
24. Guaranteed cleanup of temporary signing material.

Any failed stage prevents the private candidate artifact from being uploaded as successful.

## Produced artifacts

A successful run uploads:

### Private candidate

`MacVitals-<version>-arm64-developer-id-notarized`

It contains one version/build/commit directory with:

- `MacVitals-<version>.zip`;
- `MacVitals-<version>.dmg`;
- `BUILD_STATUS.txt`;
- `BUILD_MANIFEST.json`;
- `SHA256SUMS.txt`.

The manifest must report:

- `architectures: ["arm64"]`;
- `xcodeGenVersion: "2.45.4"` or `"2.46.0"`, matching the exact unsigned build provenance;
- `signingStatus: "developer-id-signed"`;
- `notarizationStatus: "ticket-present"`;
- the exact authorized `main` commit SHA.

### Evidence

`signed-release-evidence-<version>`

It contains:

- app and DMG codesign details;
- app and DMG notarization submission responses;
- app and DMG notarization logs;
- app and DMG Gatekeeper assessments;
- release verifier output;
- `SIGNED_RELEASE_REPORT.json` or a conservative `FAILURE.json`.

The report explicitly records `publicReleaseCreated: false`.

## Independent evidence review

A separate reviewer must verify:

- the workflow run used the intended `main` commit and version;
- the protected environment approval was legitimate;
- both Apple notarization statuses are `Accepted`;
- no notarization issue appears in either retained log;
- app and DMG authority and Team ID match the approved Developer ID identity;
- Hardened Runtime and trusted timestamp are present for the app;
- the DMG has a trusted Developer ID timestamp;
- both stapler validations and hosted Gatekeeper assessments passed;
- final checksums match the downloaded artifact;
- signed manifest preserves the supported XcodeGen version from the unsigned candidate;
- the final signed ZIP passes structure, path, entry-type, resource-limit and CRC validation;
- no secret, username or home path appears in retained evidence.

The authoring assistant must not mark `docs/audits/final-independent-audit.md` complete based on its own review.

## Clean Apple Silicon Mac validation

After downloading the private candidate onto a clean Apple Silicon Mac:

1. Verify every entry in `SHA256SUMS.txt`.
2. Confirm the executable architecture is exactly `arm64`.
3. Run strict `codesign` verification against the application.
4. Validate the stapled ticket on the application and DMG.
5. Run Gatekeeper assessment for the application and DMG.
6. Open the DMG and install the app normally.
7. Confirm the first launch does not require a manual security bypass.
8. Execute the hardened physical validation runbook against this exact signed candidate when final signed-build confirmation is required.
9. Record the signed/notarized/Gatekeeper manual gates through the hardened physical acceptance harness.

A hosted Gatekeeper pass does not replace this clean-Mac installation test.

## Publication remains separate

A successful private signed candidate is not permission to:

- create or push `v1.0.0`;
- create a GitHub Release;
- upload artifacts publicly;
- mark the signed-artifact evidence review complete without a separate reviewer.

Publication requires a separate user instruction after independent signed-artifact review and clean-Mac Gatekeeper validation are complete.
