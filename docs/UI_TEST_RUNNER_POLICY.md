# UI test runner isolation

`MacVitalsUITests-Runner.app` is an Xcode-generated XCTest host, not a MacVitals product artifact.

On unsigned self-hosted CI it must never be launched through LaunchServices. Otherwise macOS can display a Gatekeeper dialog saying the runner is damaged.

Policy:

- the primary `MacVitals` scheme contains only `MacVitalsTests` in its test action;
- `MacVitalsUITests` are compiled by the build-only `MacVitalsUITestsBuild` scheme;
- CI uses `xcodebuild ... clean build`, never the UI-test `test` action;
- CI fails if a `MacVitalsUITests-Runner` process appears;
- generated runner bundles are removed from DerivedData before and after the compile guard;
- only `MacVitals.app` may be launched by runtime and physical validation workflows.

If the macOS warning is already open, moving `MacVitalsUITests-Runner` to Trash is safe: it removes only the temporary XCTest host and does not affect `MacVitals.app` or user settings.

This preserves compile coverage for UI test sources without producing user-visible XCTest Runner prompts on a physical self-hosted Mac.
