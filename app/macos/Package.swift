// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BleWidget",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "BleWidget", targets: ["BleWidget"]),
        .executable(name: "screen-preview", targets: ["ScreenPreview"]),
    ],
    targets: [
        .target(name: "BleWidgetCore"),
        .target(name: "BleWidgetScreens", dependencies: ["BleWidgetCore"]),
        .executableTarget(
            name: "BleWidget",
            dependencies: ["BleWidgetCore", "BleWidgetScreens"]
        ),
        // `swift run screen-preview` renders every screen to PNGs; see CLAUDE.md.
        .executableTarget(
            name: "ScreenPreview",
            dependencies: ["BleWidgetCore", "BleWidgetScreens"]
        ),
        .testTarget(
            name: "BleWidgetTests",
            dependencies: ["BleWidgetCore"]
        ),
    ]
)
