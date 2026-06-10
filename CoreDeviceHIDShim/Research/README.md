# Research Artifacts

This folder contains exploratory probes used to discover the working Xcode 27 CoreDevice/UniversalHID path.

Important files:

- `probes/coredevice_universalhid_inspect.swift`: connected service inspection.
- `probes/coredevice_universalhid_tap.swift`: early tap proof.
- `probes/coredevice_universalhid_keyboard.swift`: keyboard proof.
- `probes/universalhid_report_probe.swift`: report construction experiments.
- `objc-methods.txt`: method discovery notes.

`binaries/` contains local compiled probe binaries moved from the original workspace for provenance. They are ignored by git and should not be treated as release artifacts.
