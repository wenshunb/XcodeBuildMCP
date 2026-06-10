import CoreDevice
import Foundation
import UniversalHID

enum UniversalHIDKeyboardError: Error, CustomStringConvertible {
    case usage
    case invalidUUID(String)
    case invalidUsage(String)
    case invalidServiceID(String)
    case missingHIDFeature(String)
    case missingService(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: coredevice_universalhid_keyboard <device-uuid> <usage-code> [hid-service-id]"
        case .invalidUUID(let value):
            return "invalid device UUID: \(value)"
        case .invalidUsage(let value):
            return "invalid keyboard usage code: \(value)"
        case .invalidServiceID(let value):
            return "invalid HID service id: \(value)"
        case .missingHIDFeature(let feature):
            return "CoreDevice HID capability is absent: \(feature)"
        case .missingService(let service):
            return "UniversalHID service is absent: \(service)"
        }
    }
}

@main
struct UniversalHIDKeyboard {
    static func main() async {
        do {
            try await run()
            fputs("coredevice-universalhid-keyboard: success\n", stderr)
            exit(0)
        } catch {
            fputs("coredevice-universalhid-keyboard: error: \(error)\n", stderr)
            exit(2)
        }
    }

    static func run() async throws {
        let args = CommandLine.arguments
        guard args.count == 3 || args.count == 4 else { throw UniversalHIDKeyboardError.usage }
        guard let uuid = UUID(uuidString: args[1]) else { throw UniversalHIDKeyboardError.invalidUUID(args[1]) }
        let usageCode = try parseUsage(args[2])
        let serviceID = try parseServiceID(args.count == 4 ? args[3] : "0x200")
        guard let usage = KeyboardUsage(rawValue: UInt8(usageCode)) else {
            throw UniversalHIDKeyboardError.invalidUsage(args[2])
        }

        let manager = DeviceManager(
            serviceConnection: CoreDeviceService.sharedConnection,
            allowedDeviceVisibilityClasses: [.default, .simulators]
        )
        await manager.awaitFullInitialization()
        guard let device = manager.allDevices().first(where: { $0.deviceIdentifier == uuid }) else {
            throw UniversalHIDKeyboardError.invalidUUID("\(uuid) (not found in CoreDevice DeviceManager)")
        }

        let requiredFeature = "com.apple.coredevice.feature.remote.universalhidservice"
        guard device.supportsFeature(identifiedBy: requiredFeature) else {
            throw UniversalHIDKeyboardError.missingHIDFeature(requiredFeature)
        }

        let service = try await device.getImplementation(for: CapabilityStaticMember<HIDDeviceCapability>.universalHidService)
        let connectedServiceIDs = try await service.connectedServiceIDs()
        guard connectedServiceIDs.map({ rawServiceID($0) }).contains(serviceID) else {
            throw UniversalHIDKeyboardError.missingService("0x\(String(serviceID, radix: 16)) connected=\(connectedServiceIDs)")
        }

        let down = KeyboardReport(usages: [usage]).report
        let up = KeyboardReport(usages: []).report
        try service.send(report: down, to: serviceID)
        service.sendBarrier()
        try await Task.sleep(nanoseconds: 40_000_000)
        try service.send(report: up, to: serviceID)
        service.sendBarrier()
        try await Task.sleep(nanoseconds: 100_000_000)
        fputs("coredevice-universalhid-keyboard: service=0x\(String(serviceID, radix: 16)) usage=0x\(String(usageCode, radix: 16)) connected=\(connectedServiceIDs)\n", stderr)
    }

    static func parseUsage(_ raw: String) throws -> Int {
        if raw.hasPrefix("0x") || raw.hasPrefix("0X") {
            guard let value = Int(raw.dropFirst(2), radix: 16), value >= 0, value <= UInt8.max else {
                throw UniversalHIDKeyboardError.invalidUsage(raw)
            }
            return value
        }
        guard let value = Int(raw, radix: 10), value >= 0, value <= UInt8.max else {
            throw UniversalHIDKeyboardError.invalidUsage(raw)
        }
        return value
    }

    static func parseServiceID(_ raw: String) throws -> UInt64 {
        if raw.hasPrefix("0x") || raw.hasPrefix("0X") {
            guard let value = UInt64(raw.dropFirst(2), radix: 16) else {
                throw UniversalHIDKeyboardError.invalidServiceID(raw)
            }
            return value
        }
        guard let value = UInt64(raw, radix: 10) else {
            throw UniversalHIDKeyboardError.invalidServiceID(raw)
        }
        return value
    }

    static func rawServiceID(_ serviceID: HIDServiceID) -> UInt64 {
        precondition(MemoryLayout<HIDServiceID>.size == MemoryLayout<UInt64>.size)
        return withUnsafeBytes(of: serviceID) { bytes in
            bytes.load(as: UInt64.self)
        }
    }
}
