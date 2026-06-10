import Foundation
import UniversalHID

func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

@main
struct UniversalHIDReportProbe {
    static func main() {
        fputs("probe: begin\n", stderr)
        var contact = DigitizerContact()
        fputs("probe: contact init\n", stderr)
        contact.index = 0
        fputs("probe: contact index\n", stderr)
        contact.point = HIDPoint(x: 0.5, y: 0.865, z: 0)
        fputs("probe: contact point\n", stderr)
        contact.range = true
        fputs("probe: contact range\n", stderr)
        contact.touch = true
        fputs("probe: contact touch\n", stderr)
        contact.resting = false
        fputs("probe: contact resting\n", stderr)

        fputs("probe: digitizer static reportID=\(DigitizerReport.reportID.rawValue) bits=\(DigitizerReport.initialReportBitCount)\n", stderr)
        var down = DigitizerReport(_report: HIDReport(bitCount: DigitizerReport.initialReportBitCount, id: DigitizerReport.reportID))
        fputs("probe: down init\n", stderr)
        down.contactCountMaximum = 1
        fputs("probe: down max\n", stderr)
        down.contactCount = 1
        fputs("probe: down count\n", stderr)
        down.setContact(contact, atIndex: 0)
        fputs("probe: down set contact\n", stderr)
        down.setContactIdentity(1, atIndex: 0)
        fputs("probe: down set identity\n", stderr)

        contact.touch = false
        fputs("probe: contact up touch\n", stderr)
        contact.range = false
        fputs("probe: contact up range\n", stderr)
        var up = DigitizerReport(_report: HIDReport(bitCount: DigitizerReport.initialReportBitCount, id: DigitizerReport.reportID))
        fputs("probe: up init\n", stderr)
        up.contactCountMaximum = 1
        fputs("probe: up max\n", stderr)
        up.contactCount = 0
        fputs("probe: up count\n", stderr)
        up.setContact(contact, atIndex: 0)
        fputs("probe: up set contact\n", stderr)
        up.setContactIdentity(1, atIndex: 0)
        fputs("probe: up set identity\n", stderr)

        fputs("probe: keyboard usage\n", stderr)
        let keyboardA = KeyboardUsage(rawValue: 0x04)!
        fputs("probe: keyboard down init\n", stderr)
        let keyDown = KeyboardReport(usages: [keyboardA])
        fputs("probe: keyboard up init\n", stderr)
        let keyUp = KeyboardReport(usages: [KeyboardUsage]())

        fputs("digitizer reportID=\(DigitizerReport.reportID.rawValue) bits=\(DigitizerReport.initialReportBitCount)\n", stderr)
        fputs("digitizer down data=\(hex(down.report.data))\n", stderr)
        fputs("digitizer up data=\(hex(up.report.data))\n", stderr)
        fputs("keyboard reportID=\(KeyboardReport.reportID.rawValue) bits=\(KeyboardReport.initialReportBitCount)\n", stderr)
        fputs("keyboard down desc=\(keyDown.description)\n", stderr)
        fputs("keyboard down data=\(hex(keyDown.report.data))\n", stderr)
        fputs("keyboard up desc=\(keyUp.description)\n", stderr)
        fputs("keyboard up data=\(hex(keyUp.report.data))\n", stderr)
    }
}
