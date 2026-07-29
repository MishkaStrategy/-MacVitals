# Power Model

MacVitals distinguishes:

- adapter rated or negotiated power;
- measured input power (not claimed unless a source provides it);
- signed battery power (`voltage × current`) only when both values come from the same battery snapshot/source;
- estimated system power only when measured input and aligned battery power are available;
- power balance as a derived value with explicit quality metadata.

A negative signed battery power means energy leaves the battery. The sufficiency evaluator uses a rolling time window, median smoothing, configurable discharge thresholds, minimum samples and a conflict state. Sustained battery discharge while external power is connected is the primary evidence of insufficient charging. Voltage comparison is never used to decide sufficiency.
