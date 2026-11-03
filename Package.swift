// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MonkeyBattery",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Ships as a binary XCFramework: scripts/build-app.sh has to copy and sign it
        // itself, since there is no Xcode "Embed Frameworks" phase here.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
    ],
    targets: [
        // Battery reading, estimation and alert logic — no AppKit, unit-testable.
        .target(
            name: "MonkeyBatteryCore",
            path: "Sources/MonkeyBatteryCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Menu bar app: AppKit/SwiftUI shell around the core. Sparkle lives here and
        // nowhere else — it imports AppKit, which the core target must stay free of.
        .executableTarget(
            name: "MonkeyBattery",
            dependencies: [
                "MonkeyBatteryCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/MonkeyBattery",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MonkeyBatteryTests",
            dependencies: ["MonkeyBatteryCore"],
            path: "Tests/MonkeyBatteryTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
