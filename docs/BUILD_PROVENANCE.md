# Build Provenance

Every packaged MacVitals candidate must include these files beside the ZIP and DMG:

- `BUILD_MANIFEST.json`
- `BUILD_STATUS.txt`
- `SHA256SUMS.txt`

The packaging verifier rejects missing, empty or inconsistent provenance files.

## Manifest schema v1

`BUILD_MANIFEST.json` records:

- product name;
- marketing version;
- build number;
- bundle identifier;
- minimum macOS version;
- Git commit built by the workflow;
- complete Xcode version string;
- packaged executable architectures;
- signing classification;
- notarization classification;
- exact ZIP and DMG filenames.

For MacVitals v1, the architecture list must be exactly:

```json
["arm64"]
```

Universal binaries, `x86_64`, duplicate architectures and additional slices are outside the supported scope and must be rejected by release verification.

The manifest intentionally omits usernames, runner paths, serial numbers, Apple IDs and timestamps that are unnecessary for identifying the source and toolchain.

## Signing states

The packaging script uses these explicit states:

| State | Meaning |
|---|---|
| `unsigned` | Code signing was disabled for the build. |
| `ad-hoc-signed` | A valid ad-hoc signature exists, but no trusted Developer ID identity is claimed. |
| `developer-id-signed` | The app verifies and exposes a Developer ID Application authority and team identifier. |
| `signed-unclassified` | A signature verifies, but the script cannot prove it is Developer ID. |
| `invalid-or-missing-signature` | Signing was requested, but strict verification failed. |

Only `developer-id-signed` may be described as Developer ID signed.

## Notarization states

| State | Meaning |
|---|---|
| `ticket-present` | `stapler validate` confirms a stapled notarization ticket on the application. |
| `not-notarized` | No valid stapled ticket was found. |

Only the combination `developer-id-signed` and `ticket-present`, followed by a successful Gatekeeper assessment of the final distributed artifact, may be described as signed and notarized.

## Checksum scope

`SHA256SUMS.txt` covers:

- the ZIP;
- the DMG;
- `BUILD_STATUS.txt`;
- `BUILD_MANIFEST.json`.

Any change to the binaries or their declared provenance invalidates checksum verification.

## Current CI candidates

Pull-request, main and tag-validation workflows intentionally set `CODE_SIGNING_ALLOWED=NO`. Their expected manifest state is therefore:

```text
Architectures: arm64
Signing status: unsigned
Notarization status: not-notarized
```

Tag validation cannot publish a public GitHub Release. Public publication remains blocked until a separately reviewed secret-backed Developer ID signing, notarization, stapling and Gatekeeper workflow exists.
