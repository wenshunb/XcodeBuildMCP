import CoreDevice
import CoreGraphics
import Foundation

enum DigitizerProbeError: Error, CustomStringConvertible {
    case usage
    case invalidUUID(String)
    case missingHIDFeature(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: coredevice_digitizer_probe <device-uuid> <x> <y> <edge> <target> <event|event:edge:target|event:edge:target:sleep-ms|event:edge:target:sleep-ms:x2:y2> [...]"
        case .invalidUUID(let value):
            return "invalid device UUID: \(value)"
        case .missingHIDFeature(let feature):
            return "CoreDevice HID capability is absent: \(feature)"
        }
    }
}

@inline(__always)
func enumValue<T>(_ value: UInt8, as type: T.Type) -> T {
    precondition(MemoryLayout<T>.size == MemoryLayout<UInt8>.size)
    return unsafeBitCast(value, to: T.self)
}

@main
struct DigitizerProbe {
    static func main() async {
        do {
            try await run()
            fputs("coredevice-digitizer-probe: success\n", stderr)
            exit(0)
        } catch {
            fputs("coredevice-digitizer-probe: error: \(error)\n", stderr)
            exit(2)
        }
    }

    static func run() async throws {
        let args = CommandLine.arguments
        guard args.count >= 7 else { throw DigitizerProbeError.usage }
        guard let uuid = UUID(uuidString: args[1]) else { throw DigitizerProbeError.invalidUUID(args[1]) }
        guard let x = Double(args[2]), let y = Double(args[3]),
              let edgeRaw = UInt8(args[4]), let targetRaw = UInt8(args[5]) else {
            throw DigitizerProbeError.usage
        }
        let eventRaws = try args.dropFirst(6).map { value -> UInt8 in
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            guard let parsed = UInt8(parts[0]) else { throw DigitizerProbeError.usage }
            return parsed
        }
        let sendSteps = try args.dropFirst(6).map { value -> (event: UInt8, edge: UInt8, target: UInt8, sleepMillis: UInt64, pointTwo: CGPoint?) in
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            if parts.count == 1 {
                guard let event = UInt8(parts[0]) else { throw DigitizerProbeError.usage }
                return (event, edgeRaw, targetRaw, 100, nil)
            }
            guard [3, 4, 6].contains(parts.count),
                  let event = UInt8(parts[0]),
                  let edge = UInt8(parts[1]),
                  let target = UInt8(parts[2]) else {
                throw DigitizerProbeError.usage
            }
            let sleepMillis: UInt64
            if parts.count >= 4 {
                guard let parsedSleep = UInt64(parts[3]) else { throw DigitizerProbeError.usage }
                sleepMillis = parsedSleep
            } else {
                sleepMillis = 100
            }
            let pointTwo: CGPoint?
            if parts.count == 6 {
                guard let x2 = Double(parts[4]), let y2 = Double(parts[5]) else { throw DigitizerProbeError.usage }
                pointTwo = CGPoint(x: x2, y: y2)
            } else {
                pointTwo = nil
            }
            return (event, edge, target, sleepMillis, pointTwo)
        }
        _ = eventRaws

        fputs("coredevice-digitizer-probe: sizes event=\(MemoryLayout<DigitizerEventType>.size) edge=\(MemoryLayout<DigitizerEdge>.size) target=\(MemoryLayout<DigitizerTarget>.size)\n", stderr)

        let manager = DeviceManager(
            serviceConnection: CoreDeviceService.sharedConnection,
            allowedDeviceVisibilityClasses: [.default, .simulators]
        )
        await manager.awaitFullInitialization()
        let devices = manager.allDevices()
        guard let device = devices.first(where: { $0.deviceIdentifier == uuid }) else {
            throw DigitizerProbeError.invalidUUID("\(uuid) (not found in CoreDevice DeviceManager)")
        }

        let requiredFeature = "com.apple.coredevice.feature.remote.hid.digitizer"
        guard device.supportsFeature(identifiedBy: requiredFeature) else {
            throw DigitizerProbeError.missingHIDFeature(requiredFeature)
        }

        let digitizer = try await device.getImplementation(for: CapabilityStaticMember<HIDDeviceCapability>.digitizer)
        let point = CGPoint(x: x, y: y)
        for step in sendSteps {
            let event = enumValue(step.event, as: DigitizerEventType.self)
            let edge = enumValue(step.edge, as: DigitizerEdge.self)
            let target = enumValue(step.target, as: DigitizerTarget.self)
            let pointTwoDescription = step.pointTwo.map { " pointTwo=(\($0.x),\($0.y))" } ?? ""
            fputs("coredevice-digitizer-probe: send event=\(step.event) edge=\(step.edge) target=\(step.target) point=(\(x),\(y))\(pointTwoDescription) sleepMs=\(step.sleepMillis)\n", stderr)
            try digitizer.send(pointOne: point, pointTwo: step.pointTwo, eventType: event, edge: edge, target: target)
            digitizer.sendBarrier()
            try await Task.sleep(nanoseconds: step.sleepMillis * 1_000_000)
        }
        digitizer.sendBarrier()
        let finalHoldMillis = UInt64(ProcessInfo.processInfo.environment["COREDEVICE_DIGITIZER_FINAL_HOLD_MS"] ?? "") ?? 500
        try await Task.sleep(nanoseconds: finalHoldMillis * 1_000_000)
    }
}
