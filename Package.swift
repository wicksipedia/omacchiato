// swift-tools-version:6.0
// `swift test` runs the bar's tests. install.sh builds the bar itself with
// swiftc, so this package exists for the tests.
import PackageDescription

let package = Package(
    name: "omacchiato",
    platforms: [.macOS("26.0")],
    dependencies: [.package(path: "helper/ui")],
    targets: [
        .executableTarget(
            name: "omacchiato-bar",
            dependencies: [
                .product(name: "StatusGauge", package: "ui"),
                .product(name: "BarPills", package: "ui"),
                .product(name: "WeatherPanel", package: "ui"),
                .product(name: "StatusPanel", package: "ui"),
                .product(name: "CalendarPanel", package: "ui"),
                .product(name: "AIUsagePanel", package: "ui"),
                .product(name: "PRPanel", package: "ui"),
                .product(name: "MenuBarPanel", package: "ui"),
                .product(name: "RowsPanel", package: "ui"),
                .product(name: "ActivityPanel", package: "ui"),
                .product(name: "ThemePanel", package: "ui"),
                .product(name: "AirPodsPanel", package: "ui"),
                .product(name: "SoundPanel", package: "ui"),
                .product(name: "DisplayPanel", package: "ui"),
                .product(name: "BluetoothPanel", package: "ui"),
                .product(name: "UpdatesPanel", package: "ui"),
                .product(name: "KeepAwakePanel", package: "ui"),
                .product(name: "StatsPanel", package: "ui"),
                .product(name: "PanelDesigns", package: "ui"),
                .product(name: "SettingsPanel", package: "ui"),
            ],
            path: "helper/bar",
            linkerSettings: [.unsafeFlags([
                "-F/System/Library/PrivateFrameworks", "-framework", "SkyLight", "-framework", "DisplayServices",
            ])]),
        .testTarget(name: "BarTests", dependencies: [
            "omacchiato-bar",
            .product(name: "StatusGauge", package: "ui"),
            .product(name: "BarPills", package: "ui"),
            .product(name: "WeatherPanel", package: "ui"),
            .product(name: "CalendarPanel", package: "ui"),
            .product(name: "AIUsagePanel", package: "ui"),
            .product(name: "PRPanel", package: "ui"),
            .product(name: "ActivityPanel", package: "ui"),
            .product(name: "ThemePanel", package: "ui"),
            .product(name: "AirPodsPanel", package: "ui"),
            .product(name: "SoundPanel", package: "ui"),
            .product(name: "BluetoothPanel", package: "ui"),
            .product(name: "UpdatesPanel", package: "ui"),
            .product(name: "KeepAwakePanel", package: "ui"),
            .product(name: "StatsPanel", package: "ui"),
            .product(name: "PanelDesigns", package: "ui"),
            .product(name: "SettingsPanel", package: "ui"),
        ], path: "tests/bar"),
    ],
    swiftLanguageModes: [.v5]
)
