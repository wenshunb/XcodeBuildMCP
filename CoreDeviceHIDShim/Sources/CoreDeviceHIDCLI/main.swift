import CoreDevice
import Foundation
import UniversalHID

enum CoreDeviceHIDCLIError: Error, CustomStringConvertible {
    case usage
    case invalidUUID(String)
    case invalidNumber(String)
    case invalidServiceID(String)
    case invalidTouchAction(String)
    case invalidASCII(Character)
    case missingHIDFeature(String)
    case missingService(String)

    var description: String {
        switch self {
        case .usage:
            return """
            usage:
              coredevice_hid_cli <device-uuid> tap <x> <y> [surface-width surface-height [touch-service-id]]
              coredevice_hid_cli <device-uuid> touch <x> <y> <down|up|down-up> [surface-width surface-height [touch-service-id]]
              coredevice_hid_cli <device-uuid> key <usage-code> [keyboard-service-id]
              coredevice_hid_cli <device-uuid> type <ascii-text> [keyboard-service-id]
            """
        case .invalidUUID(let value):
            return "invalid device UUID: \(value)"
        case .invalidNumber(let value):
            return "invalid number: \(value)"
        case .invalidServiceID(let value):
            return "invalid HID service id: \(value)"
        case .invalidTouchAction(let value):
            return "invalid touch action: \(value)"
        case .invalidASCII(let character):
            return "unsupported non-ASCII or unmapped character: \(character)"
        case .missingHIDFeature(let feature):
            return "CoreDevice HID capability is absent: \(feature)"
        case .missingService(let service):
            return "UniversalHID service is absent: \(service)"
        }
    }
}

struct CoreDeviceHIDContext {
    let device: RemoteDevice
    let service: any UniversalHIDService
    let connectedServiceIDs: [HIDServiceID]

    static func load(uuid: UUID) async throws -> CoreDeviceHIDContext {
        let manager = DeviceManager(
            serviceConnection: CoreDeviceService.sharedConnection,
            allowedDeviceVisibilityClasses: [.default, .simulators]
        )
        await manager.awaitFullInitialization()
        guard let device = manager.allDevices().first(where: { $0.deviceIdentifier == uuid }) else {
            throw CoreDeviceHIDCLIError.invalidUUID("\(uuid) (not found in CoreDevice DeviceManager)")
        }

        let feature = "com.apple.coredevice.feature.remote.universalhidservice"
        guard device.supportsFeature(identifiedBy: feature) else {
            throw CoreDeviceHIDCLIError.missingHIDFeature(feature)
        }

        let service = try await device.getImplementation(for: CapabilityStaticMember<HIDDeviceCapability>.universalHidService)
        let connectedServiceIDs = try await service.connectedServiceIDs()
        return CoreDeviceHIDContext(device: device, service: service, connectedServiceIDs: connectedServiceIDs)
    }

    func requireService(_ serviceID: UInt64) throws {
        if !connectedServiceIDs.map({ rawServiceID($0) }).contains(serviceID) {
            throw CoreDeviceHIDCLIError.missingService("0x\(String(serviceID, radix: 16)) connected=\(connectedServiceIDs)")
        }
    }
}

@main
struct CoreDeviceHIDCLI {
    static let defaultTouchServiceID: UInt64 = 0x101
    static let defaultKeyboardServiceID: UInt64 = 0x200
    static let defaultSurfaceWidth = 402.0
    static let defaultSurfaceHeight = 874.0

    static func main() async {
        do {
            try await run()
            fputs("coredevice-hid: success\n", stderr)
            exit(0)
        } catch {
            fputs("coredevice-hid: error: \(error)\n", stderr)
            exit(2)
        }
    }

    static func run() async throws {
        let args = CommandLine.arguments
        guard args.count >= 3 else { throw CoreDeviceHIDCLIError.usage }
        guard let uuid = UUID(uuidString: args[1]) else { throw CoreDeviceHIDCLIError.invalidUUID(args[1]) }

        let context = try await CoreDeviceHIDContext.load(uuid: uuid)
        switch args[2] {
        case "tap":
            try await runTap(args: Array(args.dropFirst(3)), context: context)
        case "touch":
            try await runTouch(args: Array(args.dropFirst(3)), context: context)
        case "key":
            try await runKey(args: Array(args.dropFirst(3)), context: context)
        case "type":
            try await runType(args: Array(args.dropFirst(3)), context: context)
        default:
            throw CoreDeviceHIDCLIError.usage
        }
    }

    static func runTap(args: [String], context: CoreDeviceHIDContext) async throws {
        guard args.count == 2 || args.count == 4 || args.count == 5 else { throw CoreDeviceHIDCLIError.usage }
        let (x, y, width, height, serviceID) = try parseTouchArguments(args)
        try context.requireService(serviceID)
        let point = normalizedPoint(x: x, y: y, width: width, height: height)
        try await sendTouchSequence(
            service: context.service,
            serviceID: serviceID,
            point: point,
            actions: [.down, .up],
            holdNanoseconds: 75_000_000
        )
        fputs("coredevice-hid: tap service=0x\(String(serviceID, radix: 16)) point=(\(x),\(y)) normalized=(\(point.x),\(point.y)) connected=\(context.connectedServiceIDs)\n", stderr)
    }

    static func runTouch(args: [String], context: CoreDeviceHIDContext) async throws {
        guard args.count == 3 || args.count == 5 || args.count == 6 else { throw CoreDeviceHIDCLIError.usage }
        let action = args[2]
        let touchArgs = [args[0], args[1]] + Array(args.dropFirst(3))
        let (x, y, width, height, serviceID) = try parseTouchArguments(touchArgs)
        try context.requireService(serviceID)
        let point = normalizedPoint(x: x, y: y, width: width, height: height)

        let actions: [TouchAction]
        switch action {
        case "down":
            actions = [.down]
        case "up":
            actions = [.up]
        case "down-up":
            actions = [.down, .up]
        default:
            throw CoreDeviceHIDCLIError.invalidTouchAction(action)
        }

        try await sendTouchSequence(
            service: context.service,
            serviceID: serviceID,
            point: point,
            actions: actions,
            holdNanoseconds: 100_000_000
        )
        fputs("coredevice-hid: touch action=\(action) service=0x\(String(serviceID, radix: 16)) point=(\(x),\(y)) normalized=(\(point.x),\(point.y)) connected=\(context.connectedServiceIDs)\n", stderr)
    }

    static func runKey(args: [String], context: CoreDeviceHIDContext) async throws {
        guard args.count == 1 || args.count == 2 else { throw CoreDeviceHIDCLIError.usage }
        let usageCode = try parseUInt8(args[0])
        let serviceID = try args.count == 2 ? parseServiceID(args[1]) : defaultKeyboardServiceID
        try context.requireService(serviceID)
        try await sendKeyPress(service: context.service, serviceID: serviceID, usages: [try keyboardUsage(usageCode)])
        fputs("coredevice-hid: key service=0x\(String(serviceID, radix: 16)) usage=0x\(String(usageCode, radix: 16)) connected=\(context.connectedServiceIDs)\n", stderr)
    }

    static func runType(args: [String], context: CoreDeviceHIDContext) async throws {
        guard args.count == 1 || args.count == 2 else { throw CoreDeviceHIDCLIError.usage }
        let serviceID = try args.count == 2 ? parseServiceID(args[1]) : defaultKeyboardServiceID
        try context.requireService(serviceID)
        for character in args[0] {
            let chord = try asciiChord(character)
            try await sendKeyPress(service: context.service, serviceID: serviceID, usages: chord)
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        fputs("coredevice-hid: type service=0x\(String(serviceID, radix: 16)) bytes=\(args[0].utf8.count) connected=\(context.connectedServiceIDs)\n", stderr)
    }

    static func parseTouchArguments(_ args: [String]) throws -> (x: Double, y: Double, width: Double, height: Double, serviceID: UInt64) {
        guard args.count == 2 || args.count == 4 || args.count == 5 else { throw CoreDeviceHIDCLIError.usage }
        let x = try parseDouble(args[0])
        let y = try parseDouble(args[1])
        let width = args.count >= 4 ? try parseDouble(args[2]) : defaultSurfaceWidth
        let height = args.count >= 4 ? try parseDouble(args[3]) : defaultSurfaceHeight
        guard width > 0, height > 0 else { throw CoreDeviceHIDCLIError.invalidNumber("\(width)x\(height)") }
        let serviceID = try args.count == 5 ? parseServiceID(args[4]) : defaultTouchServiceID
        return (x, y, width, height, serviceID)
    }

    static func parseDouble(_ raw: String) throws -> Double {
        guard let value = Double(raw) else { throw CoreDeviceHIDCLIError.invalidNumber(raw) }
        return value
    }

    static func parseUInt8(_ raw: String) throws -> UInt8 {
        let value: UInt64
        if raw.hasPrefix("0x") || raw.hasPrefix("0X") {
            guard let parsed = UInt64(raw.dropFirst(2), radix: 16) else { throw CoreDeviceHIDCLIError.invalidNumber(raw) }
            value = parsed
        } else {
            guard let parsed = UInt64(raw, radix: 10) else { throw CoreDeviceHIDCLIError.invalidNumber(raw) }
            value = parsed
        }
        guard value <= UInt8.max else { throw CoreDeviceHIDCLIError.invalidNumber(raw) }
        return UInt8(value)
    }

    static func parseServiceID(_ raw: String) throws -> UInt64 {
        if raw.hasPrefix("0x") || raw.hasPrefix("0X") {
            guard let value = UInt64(raw.dropFirst(2), radix: 16) else {
                throw CoreDeviceHIDCLIError.invalidServiceID(raw)
            }
            return value
        }
        guard let value = UInt64(raw, radix: 10) else {
            throw CoreDeviceHIDCLIError.invalidServiceID(raw)
        }
        return value
    }

    static func normalizedPoint(x: Double, y: Double, width: Double, height: Double) -> HIDPoint {
        HIDPoint(x: min(max(x / width, 0), 1), y: min(max(y / height, 0), 1), z: 0)
    }
}

enum TouchAction {
    case down
    case up
}

func sendTouchSequence(
    service: any UniversalHIDService,
    serviceID: UInt64,
    point: HIDPoint,
    actions: [TouchAction],
    holdNanoseconds: UInt64
) async throws {
    for action in actions {
        switch action {
        case .down:
            try service.resetGestureState(service: serviceID)
            try service.send(report: makeDigitizerReport(point: point, range: true, touch: true, contactCount: 1), to: serviceID)
            service.sendBarrier()
            try await Task.sleep(nanoseconds: holdNanoseconds)
        case .up:
            try service.send(report: makeDigitizerReport(point: point, range: true, touch: false, contactCount: 1), to: serviceID)
            service.sendBarrier()
            try await Task.sleep(nanoseconds: 40_000_000)
            try service.send(report: makeDigitizerReport(point: point, range: false, touch: false, contactCount: 0), to: serviceID)
            service.sendBarrier()
            try await Task.sleep(nanoseconds: 150_000_000)
        }
    }
}

func makeDigitizerReport(point: HIDPoint, range: Bool, touch: Bool, contactCount: UInt8) -> HIDReport {
    var contact = DigitizerContact()
    contact.index = 0
    contact.point = point
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

func sendKeyPress(service: any UniversalHIDService, serviceID: UInt64, usages: [KeyboardUsage]) async throws {
    try service.send(report: KeyboardReport(usages: usages).report, to: serviceID)
    service.sendBarrier()
    try await Task.sleep(nanoseconds: 35_000_000)
    try service.send(report: KeyboardReport(usages: []).report, to: serviceID)
    service.sendBarrier()
    try await Task.sleep(nanoseconds: 35_000_000)
}

func keyboardUsage(_ rawValue: UInt8) throws -> KeyboardUsage {
    guard let usage = KeyboardUsage(rawValue: rawValue) else {
        throw CoreDeviceHIDCLIError.invalidNumber("0x\(String(rawValue, radix: 16))")
    }
    return usage
}

func asciiChord(_ character: Character) throws -> [KeyboardUsage] {
    guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first, scalar.value <= 0x7f else {
        throw CoreDeviceHIDCLIError.invalidASCII(character)
    }

    let value = UInt8(scalar.value)
    if value >= 0x61 && value <= 0x7a {
        return [try keyboardUsage(0x04 + value - 0x61)]
    }
    if value >= 0x41 && value <= 0x5a {
        return [KeyboardUsage.leftShift, try keyboardUsage(0x04 + value - 0x41)]
    }
    if value >= 0x31 && value <= 0x39 {
        return [try keyboardUsage(0x1e + value - 0x31)]
    }
    if value == 0x30 {
        return [try keyboardUsage(0x27)]
    }

    let table: [Character: (UInt8, Bool)] = [
        " ": (0x2c, false), "\n": (0x28, false), "\t": (0x2b, false),
        "-": (0x2d, false), "_": (0x2d, true),
        "=": (0x2e, false), "+": (0x2e, true),
        "[": (0x2f, false), "{": (0x2f, true),
        "]": (0x30, false), "}": (0x30, true),
        "\\": (0x31, false), "|": (0x31, true),
        ";": (0x33, false), ":": (0x33, true),
        "'": (0x34, false), "\"": (0x34, true),
        "`": (0x35, false), "~": (0x35, true),
        ",": (0x36, false), "<": (0x36, true),
        ".": (0x37, false), ">": (0x37, true),
        "/": (0x38, false), "?": (0x38, true),
        "!": (0x1e, true), "@": (0x1f, true),
        "#": (0x20, true), "$": (0x21, true),
        "%": (0x22, true), "^": (0x23, true),
        "&": (0x24, true), "*": (0x25, true),
        "(": (0x26, true), ")": (0x27, true)
    ]

    guard let (usage, shifted) = table[character] else {
        throw CoreDeviceHIDCLIError.invalidASCII(character)
    }
    if shifted {
        return [KeyboardUsage.leftShift, try keyboardUsage(usage)]
    }
    return [try keyboardUsage(usage)]
}

func rawServiceID(_ serviceID: HIDServiceID) -> UInt64 {
    precondition(MemoryLayout<HIDServiceID>.size == MemoryLayout<UInt64>.size)
    return withUnsafeBytes(of: serviceID) { bytes in
        bytes.load(as: UInt64.self)
    }
}
