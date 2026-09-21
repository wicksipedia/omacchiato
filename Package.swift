// swift-tools-version:6.0
// `swift test` runs the bar's tests. install.sh builds the bar itself with
// swiftc, so this package exists for the tests.
import PackageDescription

let package = Package(
    name: "omacchiato",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "omacchiato-bar",
            path: "helper/bar",
            linkerSettings: [.unsafeFlags([
                "-F/System/Library/PrivateFrameworks", "-framework", "SkyLight", "-framework", "DisplayServices",
            ])]),
        .testTarget(name: "BarTests", dependencies: ["omacchiato-bar"], path: "tests/bar"),
    ],
    swiftLanguageModes: [.v5]
)
