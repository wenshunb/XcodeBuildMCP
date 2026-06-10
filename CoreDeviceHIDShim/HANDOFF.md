# Handoff

## What This Project Is

This is the standalone Xcode 27 CoreDevice/UniversalHID simulator input shim extracted from the LawnWatering validation work.

It is intentionally separate from AXe. AXe remains useful for accessibility snapshots and older Xcode input. This shim is the Xcode 27 input backend candidate for XcodeBuildMCP when AXe's legacy HID path is unavailable or returns false success.

## What Moved

Moved from:

```text
/Users/wenshun/Documents/workspace/LawnWatering/.codex-artifacts/coredevice-hid-probe
```

Into:

```text
/Users/wenshun/Documents/workspace/xcode27-coredevice-hid-shim
```

The old probe directory was removed after moving the relevant files.

## Validation Summary

Rebuilt from this SwiftPM package:

```text
bin/coredevice_hid_cli
sha256 84a8ab05f7e064396b141070f9b91fd4ab46b9d077447752d227fb98ffa0a1d5
```

The rebuilt binary was runtime-checked against the booted Xcode 27 simulator with an invalid service ID and failed loudly with exit code `2`, listing the connected UniversalHID services.

Validated operations:

- Standalone `tap` changed visible PlantCue state.
- Standalone `tap` launched PlantCue from SpringBoard.
- Standalone `type` inserted ASCII text.
- Standalone `key` sent Backspace and deleted text.
- Standalone `touch down-up` selected segmented controls.
- Invalid HID service failed with exit code `2` and listed connected services.
- No `XCInputRunner`, `RunnerUITests`, or XCTest input runner process was used for the standalone shim validation.

See `docs/validation.md` for the detailed evidence.

## XcodeBuildMCP Integration

The candidate XcodeBuildMCP helper is copied to:

```text
Integration/xcodebuildmcp/coredevice-hid.js
```

Recommended routing:

- Xcode `< 27`: keep existing AXe input path.
- Xcode `>= 27` and CoreDevice HID present: use this shim for input.
- CoreDevice HID absent: return a loud failure, not false success.
- XCTest input runner: keep as last resort for operations not covered by the shim.

See `docs/xcodebuildmcp-integration.md`.

## Remaining Work

- Upstream the Swift package or vendor the built binary in XcodeBuildMCP release packaging.
- Add a proper XcodeBuildMCP patch or PR once the package location is settled.
- Validate on more Xcode 27 simulator families and orientations.
- Decide whether `type replaceExisting` should grow a modifier/key-combo path or keep using XCTest fallback.
- Consider an AXe backend only after the XcodeBuildMCP integration is stable.
