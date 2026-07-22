# Privacy

MacVitals processes system measurements locally and does not transmit them.

It has no account system, analytics, telemetry, advertising, remote configuration, update tracking or cloud backend. It does not request Accessibility, Full Disk Access, administrator credentials or access to user documents.

A support bundle includes only app/build metadata, OS version, architecture, provider availability, current measurements and local sampling timings. Before encoding, MacVitals creates a separate redacted snapshot and removes the Metal GPU registry identifier. The runtime snapshot is not modified.

Support bundles exclude usernames, home paths, Mac/adapter serial numbers, stable GPU registry identifiers, Apple ID, personal files and network data. Users choose the destination and must explicitly save the JSON file; MacVitals does not upload it.
