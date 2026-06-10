# Validation Notes

Environment:

- Xcode: `27.0`, build `27A5194q`
- Simulator: iPhone 17
- Transport: DeviceHub/CoreDevice simulator visibility
- Test app: PlantCue, bundle `com.wb.plantcue`

Validated standalone CLI binary:

```text
bin/coredevice_hid_cli.validated
sha256 77c503dffeeaddb1b880ec20e5bcf8321c45a26ccbb0e471e21abe34c07dba3a
```

Rebuilt from this package:

```text
bin/coredevice_hid_cli
sha256 84a8ab05f7e064396b141070f9b91fd4ab46b9d077447752d227fb98ffa0a1d5
```

Runtime check for the rebuilt binary:

```text
bin/coredevice_hid_cli D2E7C171-791B-430F-ADF3-7BF3E0ED7E09 tap 10 10 402 874 0x999
```

Result:

```text
exit 2
coredevice-hid: error: UniversalHID service is absent: 0x999 connected=[mainTouchscreen(0x101), touchscreen(0x104), mainKeyboard(0x200), mainScreenButtons(0x402), avpCustom(0x500), touchscreenGesture(0x501)]
```

## Commands Proven

Tap:

- Tapped PlantCue onboarding controls.
- Tapped PlantCue icon on SpringBoard and launched the app.
- BackBoard logs showed real down/up touch delivery to SpringBoard.

Touch:

- `touch down-up` selected PlantCue segmented controls.
- `touch down` and `touch up` were exercised independently during probe work.

Keyboard:

- `type bc1` inserted visible ASCII text.
- `key 0x2a` sent Backspace and deleted the final character.

Failure behavior:

- Invalid service `0x999` exited `2`.
- Error included the absent service and connected services:

```text
coredevice-hid: error: UniversalHID service is absent: 0x999 connected=[mainTouchscreen(0x101), touchscreen(0x104), mainKeyboard(0x200), mainScreenButtons(0x402), avpCustom(0x500), touchscreenGesture(0x501)]
```

XCTest:

- Standalone validation did not start an XCTest runner.
- Process checks during validation showed no `XCInputRunner`, `RunnerUITests`, or `xctest-input-runner`.

## Service IDs

Connected services observed on the validated simulator:

```text
mainTouchscreen(0x101)
touchscreen(0x104)
mainKeyboard(0x200)
mainScreenButtons(0x402)
avpCustom(0x500)
touchscreenGesture(0x501)
```

Important discovery:

- `findServiceMatching(HIDUsage(page: 13, usage: 4))` returned `0`, which behaved like an index-like value and was not the working raw service ID.
- The working default touchscreen service was `0x101`.

## Coordinate Model

UniversalHID digitizer reports expect normalized coordinates.

The validated simulator surface was:

```text
402x874
```

XcodeBuildMCP should pass the best known surface dimensions from its accessibility snapshot instead of relying on the CLI default.
