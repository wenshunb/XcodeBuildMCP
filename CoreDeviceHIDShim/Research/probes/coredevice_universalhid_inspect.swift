import CoreDevice
import Foundation
import UniversalHID

enum UniversalHIDInspectError: Error, CustomStringConvertible {
    case usage
    case invalidUUID(String)
    case missingHIDFeature(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: coredevice_universalhid_inspect <device-uuid>"
        case .invalidUUID(let value):
            return "invalid device UUID: \(value)"
        case .missingHIDFeature(let feature):
            return "CoreDevice HID capability is absent: \(feature)"
        }
    }
}

@main
struct UniversalHIDInspect {
    static func main() async {
        do {
            try await run()
            fputs("coredevice-universalhid-inspect: success\n", stderr)
            exit(0)
        } catch {
            fputs("coredevice-universalhid-inspect: error: \(error)\n", stderr)
            exit(2)
        }
    }

    static func run() async throws {
        let args = CommandLine.arguments
        guard args.count == 2 else { throw UniversalHIDInspectError.usage }
        guard let uuid = UUID(uuidString: args[1]) else { throw UniversalHIDInspectError.invalidUUID(args[1]) }

        let manager = DeviceManager(
            serviceConnection: CoreDeviceService.sharedConnection,
            allowedDeviceVisibilityClasses: [.default, .simulators]
        )
        await manager.awaitFullInitialization()
        let devices = manager.allDevices()
        guard let device = devices.first(where: { $0.deviceIdentifier == uuid }) else {
            throw UniversalHIDInspectError.invalidUUID("\(uuid) (not found in CoreDevice DeviceManager)")
        }

        let requiredFeature = "com.apple.coredevice.feature.remote.universalhidservice"
        guard device.supportsFeature(identifiedBy: requiredFeature) else {
            throw UniversalHIDInspectError.missingHIDFeature(requiredFeature)
        }

        let service = try await device.getImplementation(for: CapabilityStaticMember<HIDDeviceCapability>.universalHidService)
        fputs("coredevice-universalhid-inspect: connectedServiceIDs=\(try await service.connectedServiceIDs())\n", stderr)
        let connectedServices = try await service.connectedServices()
        fputs("coredevice-universalhid-inspect: connectedServices=\(connectedServices.count) start=\(connectedServices.startIndex) end=\(connectedServices.endIndex) isEmpty=\(connectedServices.isEmpty)\n", stderr)
        fputs("coredevice-universalhid-inspect: firstIsNil=\(connectedServices.first == nil)\n", stderr)
        for properties in connectedServices {
            let usages = properties.deviceUsagePairs.map { "\($0.page):\($0.usage)" }.joined(separator: ",")
            fputs("service id=\(properties.serviceID) primary=\(properties.primaryUsagePair.page):\(properties.primaryUsagePair.usage) usages=[\(usages)] product=\(properties.product ?? "-") hint=\(properties.deviceTypeHint ?? "-") desc=\(properties.description)\n", stderr)
        }
        fputs("coredevice-universalhid-inspect: primaryKeyboard=\(String(describing: try await service.primaryKeyboard()))\n", stderr)
        fputs("coredevice-universalhid-inspect: primaryPointer=\(String(describing: try await service.primaryPointer()))\n", stderr)
        fputs("coredevice-universalhid-inspect: matchTouchscreen=\(String(describing: try await service.findServiceMatching(usage: HIDUsage(page: 13, usage: 4))))\n", stderr)
        fputs("coredevice-universalhid-inspect: matchKeyboard=\(String(describing: try await service.findServiceMatching(usage: HIDUsage(page: 1, usage: 6))))\n", stderr)
    }
}
