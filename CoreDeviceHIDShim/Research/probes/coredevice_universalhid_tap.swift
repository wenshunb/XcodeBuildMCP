import CoreDevice
import Foundation
import UniversalHID

enum UniversalHIDTapError: Error, CustomStringConvertible {
    case usage
    case invalidUUID(String)
    case missingHIDFeature(String)
    case missingService(String)
    case invalidServiceID(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: coredevice_universalhid_tap <device-uuid> <x> <y> [surface-width surface-height [hid-service-id]]"
        case .invalidUUID(let value):
            return "invalid device UUID: \(value)"
        case .missingHIDFeature(let feature):
            return "CoreDevice HID capability is absent: \(feature)"
        case .missingService(let usage):
            return "UniversalHID service is absent: \(usage)"
        case .invalidServiceID(let value):
            return "invalid HID service id: \(value)"
        }
    }
}

func makeDigitizerReport(x: Double, y: Double, range: Bool, touch: Bool, contactCount: UInt8) -> HIDReport {
    var contact = DigitizerContact()
    contact.index = 0
    contact.point = HIDPoint(x: x, y: y, z: 0)
    contact.range = range
    contact.touch = touch
    contact.resting = false

    var report = DigitizerReport(_report: HIDReport(bitCount: DigitizerReport.initialReportBitCount, id: DigitizerReport.reportID))
    report.contactCountMaximum = 1
    report.contactCount = contactCount
    report.setContact(contact, atIndex: 0)
    report.setContactIdentity(1, atIndex: 0)
    return report.report
}

@main
struct UniversalHIDTap {
    static func main() async {
        do {
            try await run()
            fputs("coredevice-universalhid-tap: success\n", stderr)
            exit(0)
        } catch {
            fputs("coredevice-universalhid-tap: error: \(error)\n", stderr)
            exit(2)
        }
    }

    static func run() async throws {
        let args = CommandLine.arguments
        guard args.count == 4 || args.count == 6 || args.count == 7 else { throw UniversalHIDTapError.usage }
        guard let uuid = UUID(uuidString: args[1]) else { throw UniversalHIDTapError.invalidUUID(args[1]) }
        guard let x = Double(args[2]), let y = Double(args[3]) else { throw UniversalHIDTapError.usage }
        let width = args.count >= 6 ? Double(args[4]) : 402
        let height = args.count >= 6 ? Double(args[5]) : 874
        guard let width, let height, width > 0, height > 0 else { throw UniversalHIDTapError.usage }
        let serviceIDValue = try parseServiceID(args.count == 7 ? args[6] : "0x101")

        let manager = DeviceManager(
            serviceConnection: CoreDeviceService.sharedConnection,
            allowedDeviceVisibilityClasses: [.default, .simulators]
        )
        await manager.awaitFullInitialization()
        let devices = manager.allDevices()
        guard let device = devices.first(where: { $0.deviceIdentifier == uuid }) else {
            throw UniversalHIDTapError.invalidUUID("\(uuid) (not found in CoreDevice DeviceManager)")
        }

        let requiredFeature = "com.apple.coredevice.feature.remote.universalhidservice"
        guard device.supportsFeature(identifiedBy: requiredFeature) else {
            throw UniversalHIDTapError.missingHIDFeature(requiredFeature)
        }

        let service = try await device.getImplementation(for: CapabilityStaticMember<HIDDeviceCapability>.universalHidService)
        let connectedServiceIDs = try await service.connectedServiceIDs()
        let connectedServiceIDValues = connectedServiceIDs.map { rawServiceID($0) }
        guard connectedServiceIDValues.contains(serviceIDValue) else {
            throw UniversalHIDTapError.missingService("0x\(String(serviceIDValue, radix: 16)) connected=\(connectedServiceIDs)")
        }
        let normalizedX = min(max(x / width, 0), 1)
        let normalizedY = min(max(y / height, 0), 1)
        fputs("coredevice-universalhid-tap: service=0x\(String(serviceIDValue, radix: 16)) point=(\(x),\(y)) normalized=(\(normalizedX),\(normalizedY)) surface=(\(width),\(height)) connected=\(connectedServiceIDs)\n", stderr)

        try service.resetGestureState(service: serviceIDValue)
        try service.send(report: makeDigitizerReport(x: normalizedX, y: normalizedY, range: true, touch: true, contactCount: 1), to: serviceIDValue)
        service.sendBarrier()
        try await Task.sleep(nanoseconds: 80_000_000)
        try service.send(report: makeDigitizerReport(x: normalizedX, y: normalizedY, range: true, touch: false, contactCount: 1), to: serviceIDValue)
        service.sendBarrier()
        try await Task.sleep(nanoseconds: 40_000_000)
        try service.send(report: makeDigitizerReport(x: normalizedX, y: normalizedY, range: false, touch: false, contactCount: 0), to: serviceIDValue)
        service.sendBarrier()
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    static func parseServiceID(_ raw: String) throws -> UInt64 {
        if raw.hasPrefix("0x") || raw.hasPrefix("0X") {
            guard let value = UInt64(raw.dropFirst(2), radix: 16) else {
                throw UniversalHIDTapError.invalidServiceID(raw)
            }
            return value
        }
        guard let value = UInt64(raw, radix: 10) else {
            throw UniversalHIDTapError.invalidServiceID(raw)
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
