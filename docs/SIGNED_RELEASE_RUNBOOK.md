# Private Signed Release Candidate Runbook

This runbook creates a **private** Developer ID signed and notarized MacVitals candidate. It does not merge branches, create a tag or publish a GitHub Release.

The signed pipeline supports Apple Silicon (`arm64`) only. Intel and universal artifacts remain unsupported and are verification failures.

## Safety contract

The workflow `.github/workflows/signed-release-candidate.yml`:

- runs only through `workflow_dispatch`;
- requires the exact authorization phrase `SIGN_MACVITALS_RELEASE_CANDIDATE`;
- checks out an explicitly supplied 40-character commit SHA;
- uses the protected `signed-release` GitHub environment;
- has read-only repository permissions;
- routes all credential-backed execution through `scripts/signed_release_entrypoint.py`;
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

Create a GitHub environment named `signed-release` and configure required reviewers before adding secrets. Restrict deployment branches to the intended release branch or protected tags as appropriate for the repository policy.

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

1. Confirm the intended commit is already present in `mishkacher/-MacVitals`.
2. Confirm its Pull Request workflow is completely green.
3. Confirm the exact commit has passed the unsigned arm64 package verifier and hosted runtime/privacy gates.
4. Review open physical, accessibility and independent-audit gates. Signing does not close them.
5. Record the exact commit SHA in the release checkpoint.
6. Obtain explicit user authorization for a private signed candidate.

Do not sign an unreviewed moving branch name. Always sign an immutable SHA.

## Manual workflow invocation

Open **Actions → Signed Release Candidate → Run workflow** and supply:

- `version`: the intended numeric version, such as `1.0.0`;
- `expected_commit`: the exact lowercase 40-character SHA;
- `authorization`: `SIGN_MACVITALS_RELEASE_CANDIDATE`.

The workflow checks out that SHA directly. A mismatch between the requested SHA and the checkout is a hard failure before signing material is used.

## Pipeline stages

The workflow, `scripts/signed_release_entrypoint.py` and `scripts/sign_notarize_release.py` perform:

1. Python compilation and deterministic self-tests, including adversarial path-isolation cases.
2. Resolution of signed output, work and evidence roots; all three must be mutually non-overlapping strict repository children with no symlink escape.
3. SwiftFormat lint and native arm64 unit tests.
4. Temporary keychain creation and Developer ID certificate import.
5. A fresh unsigned arm64 archive through the existing package/release verifier.
6. Exact manifest, version, build, commit and architecture validation.
7. Developer ID Application signing with Hardened Runtime, trusted timestamp and project entitlements.
8. Strict app signature, authority, Team ID, timestamp and arm64 verification.
9. Application ZIP submission to Apple notarization with `--wait`.
10. Retention of the application submission response and notarization log.
11. Stapling and validation of the application ticket.
12. Creation of the final ZIP and DMG from the stapled application.
13. Developer ID signing and verification of the DMG.
14. DMG submission to Apple notarization with `--wait`.
15. Retention of the DMG submission response and notarization log.
16. Stapling and validation of the DMG ticket.
17. Gatekeeper assessment of both the application and DMG.
18. Regeneration of signed/notarized provenance and SHA-256 files after stapling.
19. Full `verify_release.sh` validation against the exact requested commit.
20. Privacy scanning of text evidence and metadata.
21. Upload of private candidate and evidence workflow artifacts.
22. Guaranteed cleanup of temporary signing material.

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
- `signingStatus: "developer-id-signed"`;
- `notarizationStatus: "ticket-present"`;
- the exact authorized commit SHA.

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

- the workflow run used the intended commit and version;
- the protected environment approval was legitimate;
- both Apple notarization statuses are `Accepted`;
- no notarization issue appears in either retained log;
- app and DMG authority and Team ID match the approved Developer ID identity;
- Hardened Runtime and trusted timestamp are present for the app;
- the DMG has a trusted Developer ID timestamp;
- both stapler validations and Gatekeeper assessments passed;
- final checksums match the downloaded artifact;
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
8. Execute the physical validation runbook against this exact signed candidate.
9. Record the signed/notarized/Gatekeeper manual gates through the physical acceptance harness.

A hosted Gatekeeper pass does not replace this clean-Mac installation test.

## Publication remains separate

A successful private signed candidate is not permission to:

- merge the Draft PR;
- create or push `v1.0.0`;
- create a GitHub Release;
- upload artifacts publicly;
- mark the independent audit complete.

Publication requires a separate user instruction after physical validation, manual accessibility/visual review, independent reviewer sign-off and clean-Mac Gatekeeper validation are complete.
