# Sensor Compatibility

| Metric | Source | Apple Silicon | Intel | Laptop | Desktop | Adapter needed | Reliability | Public API | Missing-data behavior |
|---|---|---:|---:|---:|---:|---:|---|---:|---|
| CPU total/user/system/idle | Mach `host_statistics` | Yes | Yes | Yes | Yes | No | High | Yes | Temporarily unavailable; baseline reset |
| Physical/active/wired/compressed memory | Mach `host_statistics64` | Yes | Yes | Yes | Yes | No | High | Yes | Provider error, app continues |
| Battery percentage/state/time | IOKit Power Sources | Expected | Expected | Yes | N/A | No | High | Yes | Battery section reports absent |
| Battery voltage/current/cycles/temperature | `AppleSmartBattery` IORegistry keys | Capability checked | Capability checked | Model-dependent | N/A | No | Experimental | Registry API public; keys not guaranteed | Omitted and marked unavailable |
| Adapter presence/rated power | `IOPSCopyExternalPowerAdapterDetails` | Expected | Expected | Yes | Model-dependent | Yes | Medium/high | Yes | Adapter unavailable |
| Adapter measured input power | No universal source in v1 | No claim | No claim | No claim | No claim | Yes | Unsupported | — | Explicitly unavailable |
| GPU identity/Metal capability | Metal | Yes | Model-dependent | Yes | Yes | No | High | Yes | GPU unavailable |
| Whole-system GPU utilization | No universal public API selected | Unsupported | Unsupported | Unsupported | Unsupported | No | Honest unsupported | — | Message: unavailable on this configuration |
| Charger sufficiency | Derived from aligned battery/external-power samples | Yes when inputs exist | Yes when inputs exist | Yes | N/A | Yes | Medium, confidence reported | Derived | Unknown when required inputs are missing |

Runtime capability detection is authoritative; model names are not used as proof of sensor availability.
