# AXe Relationship

AXe is not using this CoreDevice shim.

The current AXe input path is:

```text
AXe CLI
  -> FBSimulatorControl
  -> FBSimulatorHID / FBSimulatorHIDEvent
  -> SimulatorKit.SimDeviceLegacyHIDClient / IndigoHID
```

XcodeBuildMCP currently shells out to AXe for commands like `tap`, `touch`, `type`, and `key`. In the bundled XcodeBuildMCP package, AXe is shipped with prebuilt `FBSimulatorControl` frameworks under `bundled/` and `bundled-xcode27/`.

`FBSimulatorControl` is not a git submodule in that installed package. Upstream AXe links it as a binary artifact, not as a live source checkout.

Recommended project relationship:

```text
XcodeBuildMCP
  -> AXe for accessibility snapshots and older-Xcode input
  -> CoreDevice HID shim for Xcode 27 input
  -> XCTest input runner as last resort
```

Forking AXe is optional future work. It makes sense only if AXe itself should expose a `coredevice` input backend for non-XcodeBuildMCP consumers.
