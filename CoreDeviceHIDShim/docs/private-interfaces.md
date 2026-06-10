# Private Interfaces

The shim imports Apple private modules from Xcode 27:

- `CoreDevice`
- `UniversalHID`

Swift interface files live under:

```text
PrivateInterfaces/
```

They are minimal handoff interfaces, not public SDK contracts. Treat them as Xcode-version-sensitive. If Xcode 27 changes these APIs before GM, regenerate or update the interfaces and rebuild.

Runtime frameworks are expected at:

```text
/Library/Developer/PrivateFrameworks/CoreDevice.framework
/Library/Developer/PrivateFrameworks/CoreDevice.framework/Versions/A/Frameworks/UniversalHID.framework
```

The package manifest passes those framework paths through unsafe SwiftPM flags because these are private frameworks outside the public SDK module map.
