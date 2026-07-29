# Contributing

Use an Apple Silicon Mac with Xcode 16+, Swift 6 and macOS 13+. MacVitals v1 intentionally targets `arm64` only; do not add Intel or universal build paths without an explicit product-scope decision.

Keep providers read-only, capability checked and explicit about source/quality. Add deterministic unit tests for calculations and do not claim hardware coverage without evidence.

Run `make test`, `make lint` and `make validate-tooling` before opening a pull request. Native builds, tests, packaging and runtime smoke belong on an Apple Silicon Mac runner; Linux checks are limited to repository validation, documentation, licenses and secret scanning.
