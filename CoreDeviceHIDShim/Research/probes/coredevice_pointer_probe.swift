import CoreDevice
import CoreGraphics
import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case usage
    case invalidUUID(String)
    case missingHIDFeature(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: coredevice_pointer_probe <device-uuid> <x> <y>"
        case .invalidUUID(let value):
            return "invalid device UUID: \(value)"
        case .missingHIDFeature(let feature):
            return "CoreDevice HID capability is absent: \(feature)"
        }
    }
}

@main
struct Probe {
    static func main() async {
        do {
            try await run()
            fputs("coredevice-pointer-probe: success\n", stderr)
            exit(0)
        } catch {
            fputs("coredevice-pointer-probe: error: \(error)\n", stderr)
            exit(2)
        }
    }

    static func run() async throws {
        let args = CommandLine.arguments
        guard args.count == 4 else { throw ProbeError.usage }
        guard let uuid = UUID(uuidString: args[1]) else { throw ProbeError.invalidUUID(args[1]) }
        guard let x = Double(args[2]), let y = Double(args[3]) else { throw ProbeError.usage }

        let manager = DeviceManager(
            serviceConnection: CoreDeviceService.sharedConnection,
            allowedDeviceVisibilityClasses: [.default, .simulators]
        )
        await manager.awaitFullInitialization()
        let devices = manager.allDevices()
        fputs("coredevice-pointer-probe: DeviceManager returned \(devices.count) devices\n", stderr)
        for visibleDevice in devices {
            fputs("coredevice-pointer-probe: visible device \(visibleDevice.deviceIdentifier)\n", stderr)
        }
        guard let device = devices.first(where: { $0.deviceIdentifier == uuid }) else {
            throw ProbeError.invalidUUID("\(uuid) (not found in CoreDevice DeviceManager)")
        }
        let featureIDs = [
            "com.apple.coredevice.feature.remote.hid.digitizer",
            "com.apple.coredevice.feature.remote.hid.keyboard",
            "com.apple.coredevice.feature.remote.universalhidservice",
            "com.apple.dt.remote.hid"
        ]
        for featureID in featureIDs {
            fputs("coredevice-pointer-probe: supports \(featureID): \(device.supportsFeature(identifiedBy: featureID))\n", stderr)
        }
        let requiredFeature = "com.apple.coredevice.feature.remote.hid.digitizer"
        guard device.supportsFeature(identifiedBy: requiredFeature) else {
            throw ProbeError.missingHIDFeature(requiredFeature)
        }

        let pointer = try await device.getImplementation(for: CapabilityStaticMember<HIDDeviceCapability>.pointer)
        let point = CGPoint(x: x, y: y)
        try await pointer.send(movedTo: point)
        try await pointer.send(button: 1, phase: .down, clicks: 1, at: point)
        try await pointer.send(button: 1, phase: .up, clicks: 1, at: point)
        pointer.sendBarrier()
    }
}
