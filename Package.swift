// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DualSenseTrackpad",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "dualsense-trackpad", targets: ["DualSenseTrackpad"]),
    ],
    targets: [
        // Pure Swift: HID report parsing + gesture recognition. No Apple frameworks,
        // so it builds and tests on any platform.
        .target(name: "DualSenseCore"),
        // macOS glue: IOKit HID input + CoreGraphics event injection.
        .executableTarget(name: "DualSenseTrackpad", dependencies: ["DualSenseCore"]),
        .testTarget(name: "DualSenseCoreTests", dependencies: ["DualSenseCore"]),
    ]
)
