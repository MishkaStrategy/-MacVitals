# Canonical runner selectors

Every GitHub Actions job must use exactly one selector:

```yaml
runs-on: [self-hosted, fast]
runs-on: [self-hosted, docker]
runs-on: [self-hosted, backtester]
runs-on: [self-hosted, macOS, ARM64]
```

No additional labels, hosted runners, dynamic selectors, machine names, `Linux`, `X64`, or legacy `backtest` are allowed. Native MacVitals jobs use `[self-hosted, macOS, ARM64]`.
