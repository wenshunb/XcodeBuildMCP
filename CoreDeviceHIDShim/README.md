# Xcode 27 CoreDevice HID Shim

Standalone CoreDevice/UniversalHID input shim for iOS simulators on Xcode 27.

This project contains the proven local CLI that bypasses AXe's legacy `FBSimulatorControl` HID path and sends input through CoreDevice `UniversalHIDService`.

## Status

Validated locally with Xcode 27.0 beta build `27A5194q` against an iPhone 17 simulator using DeviceHub. The shim produced visible state changes in PlantCue and SpringBoard without starting an XCTest runner.

Supported operations:

- `tap`
- `touch down`
- `touch up`
- `touch down-up`
- `key`
- `type` ASCII text

The CLI fails loudly when the CoreDevice HID capability or requested UniversalHID service is absent.

## Build

```sh
cd /Users/wenshun/Documents/workspace/xcode27-coredevice-hid-shim
scripts/build.sh
```

The built executable is copied to:

```text
bin/coredevice_hid_cli
```

## Usage

```text
coredevice_hid_cli <device-uuid> tap <x> <y> [surface-width surface-height [touch-service-id]]
coredevice_hid_cli <device-uuid> touch <x> <y> <down|up|down-up> [surface-width surface-height [touch-service-id]]
coredevice_hid_cli <device-uuid> key <usage-code> [keyboard-service-id]
coredevice_hid_cli <device-uuid> type <ascii-text> [keyboard-service-id]
```

Default services discovered on the validated Xcode 27 simulator:

- Touchscreen: `0x101`
- Keyboard: `0x200`

Default surface size in the standalone CLI is `402x874`; XcodeBuildMCP integration should pass screen dimensions from the accessibility snapshot where available.

## Layout

- `Sources/CoreDeviceHIDCLI/main.swift`: standalone shim CLI.
- `PrivateInterfaces/`: minimal Swift interfaces for private Xcode 27 modules.
- `Integration/xcodebuildmcp/`: candidate XcodeBuildMCP adapter helper.
- `Research/probes/`: exploratory probes used to discover service IDs and report formats.
- `docs/`: handoff notes, validation evidence, and integration guidance.

## Constraints

This uses Apple private Xcode frameworks:

- `/Library/Developer/PrivateFrameworks/CoreDevice.framework`
- `/Library/Developer/PrivateFrameworks/CoreDevice.framework/Versions/A/Frameworks/UniversalHID.framework`

It is intended as a simulator automation compatibility shim, not app-store code.
