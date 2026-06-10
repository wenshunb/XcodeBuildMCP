# XcodeBuildMCP Integration

## Goal

Route XcodeBuildMCP input through CoreDevice/UniversalHID on Xcode 27 while leaving existing AXe behavior intact for older Xcodes.

## Recommended Routing

```text
tap/type/touch/key request
  -> detect active Xcode major version
  -> Xcode < 27: existing AXe path
  -> Xcode >= 27: CoreDevice HID shim
      -> CoreDevice HID capability absent: loud failure
      -> requested UniversalHID service absent: loud failure
      -> covered command succeeds: return success
      -> uncovered command: XCTest fallback only if explicitly allowed
```

## Candidate Helper

The candidate Node helper is copied here:

```text
Integration/xcodebuildmcp/coredevice-hid.js
```

It resolves the shim in this order:

1. `XCODEBUILDMCP_COREDEVICE_HID_CLI`
2. package-local `bin/coredevice_hid_cli`
3. old local probe location, for compatibility with earlier local validation

For upstreaming, remove the old probe-location fallback and keep the environment variable plus package-local binary.

## Patched Local Files During Validation

The local npm-exec XcodeBuildMCP package was patched under:

```text
/Users/wenshun/.npm/_npx/99336612077b7094/node_modules/xcodebuildmcp
```

Files touched:

- `build/mcp/tools/ui-automation/shared/coredevice-hid.js`
- `build/mcp/tools/ui-automation/tap.js`
- `build/mcp/tools/ui-automation/type_text.js`
- `build/mcp/tools/ui-automation/touch.js`
- `build/mcp/tools/ui-automation/key_press.js`
- `build/mcp/tools/ui-automation/bin/coredevice_hid_cli`

Validation used fresh module imports because the live MCP server had already loaded the old JavaScript modules. A running MCP server must be restarted to load the patched files.

## Fallback Policy

Keep XCTest fallback as a last resort, not as the primary Xcode 27 input path.

Suggested initial policy:

- `tap`: CoreDevice first on Xcode 27; XCTest fallback only for unexpected shim execution errors.
- `type`: CoreDevice first for ASCII append; XCTest fallback for `replaceExisting`.
- `touch`: CoreDevice only on Xcode 27; fail loudly if unavailable.
- `key`: CoreDevice only on Xcode 27; fail loudly if unavailable.

Capability and service absence should not fall through to XCTest silently because that hides environment incompatibility.
