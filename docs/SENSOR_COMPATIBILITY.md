# Sensor Compatibility

MacVitals v1 supports Apple Silicon (`arm64`) Macs running macOS 13 or later. Intel compatibility is intentionally outside the supported scope.

| Metric | Source | Apple Silicon | Laptop | Desktop | Adapter needed | Reliability | Public API | Missing-data behavior |
|---|---|---|---:|---:|---:|---|---:|---|
| CPU total/user/system/idle | Mach `host_statistics` | CI smoke verified on hosted ARM; physical validation pending | Yes | Yes | No | High | Yes | Temporarily unavailable; baseline reset |
| Physical/active/wired/compressed memory | Mach `host_statistics64` | CI smoke verified on hosted ARM; physical validation pending | Yes | Yes | No | High | Yes | Provider error, app continues |
| Memory pressure level | `DispatchSourceMemoryPressure` | Build/test verified on ARM; pressure transitions need physical stress validation | Yes | Yes | No | High for OS pressure events | Yes | `unknown`; percent threshold remains separate |
| Battery percentage/state/time | IOKit Power Sources | Provider build verified; physical battery transitions pending | Yes | N/A | No | High | Yes | Battery section reports absent |
| Battery voltage/current/cycles/temperature | `AppleSmartBattery` IORegistry keys | Capability checked at runtime | Model-dependent | N/A | No | Experimental | Registry API public; keys not guaranteed | Omitted and marked unavailable |
| Adapter presence/rated power | `IOPSCopyExternalPowerAdapterDetails` | Provider build verified; real adapters pending | Yes | Model-dependent | Yes | Medium/high | Yes | Adapter unavailable |
| Adapter measured input power | No universal source in v1 | No claim | No claim | No claim | Yes | Unsupported | — | Explicitly unavailable |
| GPU identity/Metal capability | Metal | CI smoke verified on hosted ARM | Yes | Yes | No | High | Yes | GPU unavailable |
| Whole-system GPU utilization | No universal public API selected | Unsupported | Unsupported | Unsupported | No | Honest unsupported | — | Message: unavailable on this configuration |
| Charger sufficiency | Derived from aligned battery/external-power samples | Unit tested; physical charger matrix pending | Yes | N/A | Yes | Medium, confidence reported | Derived | Unknown when required inputs are missing |

Runtime capability detection is authoritative; model names are not used as proof of sensor availability. Hosted CI evidence proves arm64 compilation and functional smoke behavior only. It does not replace physical-device compatibility or calibration testing.

Release verification rejects universal binaries and binaries containing `x86_64`; the distributable executable must contain exactly `arm64`.
