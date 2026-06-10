// swift-tools-version: 6.2

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let privateInterfaces = "\(packageRoot)/PrivateInterfaces"
let coreDeviceFrameworks = "/Library/Developer/PrivateFrameworks"
let universalHIDFrameworks = "\(coreDeviceFrameworks)/CoreDevice.framework/Versions/A/Frameworks"

let package = Package(
    name: "Xcode27CoreDeviceHIDShim",
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .executable(name: "coredevice_hid_cli", targets: ["CoreDeviceHIDCLI"])
    ],
    targets: [
        .executableTarget(
            name: "CoreDeviceHIDCLI",
            path: "Sources/CoreDeviceHIDCLI",
            swiftSettings: [
                .unsafeFlags(["-I", privateInterfaces])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", coreDeviceFrameworks,
                    "-F", universalHIDFrameworks,
                    "-framework", "CoreDevice",
                    "-framework", "UniversalHID"
                ])
            ]
        )
    ]
)
