# Temperature sensor policy

MacVitals prefers the Apple SMC `TCMz` CPU die-hotspot key when the current Apple Silicon model exposes it. Because Apple changes sensor maps between SoC generations, the provider probes a small set of known processor-temperature keys and uses the hottest plausible processor reading when `TCMz` is absent.

All processor readings are treated as experimental hardware telemetry and are rejected outside 5–130 °C. Battery temperature remains a direct IOKit fallback and is shown separately in the temperature detail view.
