// swift-tools-version:6.0
// Open this package in Xcode to preview the bar's views. A preview fails in
// the root package, because Xcode hosts it in the bar's executable target.
import PackageDescription

let package = Package(
    name: "BarUI",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "StatusGauge", targets: ["StatusGauge"]),
        .library(name: "BarPills", targets: ["BarPills"]),
        .library(name: "WeatherPanel", targets: ["WeatherPanel"]),
        .library(name: "StatusPanel", targets: ["StatusPanel"]),
        .library(name: "CalendarPanel", targets: ["CalendarPanel"]),
        .library(name: "AIUsagePanel", targets: ["AIUsagePanel"]),
        .library(name: "PRPanel", targets: ["PRPanel"]),
        .library(name: "MenuBarPanel", targets: ["MenuBarPanel"]),
        .library(name: "RowsPanel", targets: ["RowsPanel"]),
        .library(name: "ActivityPanel", targets: ["ActivityPanel"]),
        .library(name: "ThemePanel", targets: ["ThemePanel"]),
        .library(name: "AirPodsPanel", targets: ["AirPodsPanel"]),
    ],
    targets: [
        .target(name: "StatusGauge"),
        .target(name: "BarPills"),
        .target(name: "WeatherPanel"),
        .target(name: "StatusPanel", dependencies: ["StatusGauge"]),
        .target(name: "CalendarPanel", dependencies: ["StatusPanel"]),
        .target(name: "AIUsagePanel", dependencies: ["StatusPanel"]),
        .target(name: "PRPanel", dependencies: ["StatusPanel"]),
        .target(name: "MenuBarPanel", dependencies: ["StatusPanel"]),
        .target(name: "RowsPanel", dependencies: ["StatusPanel"]),
        .target(name: "ActivityPanel", dependencies: ["StatusPanel"]),
        .target(name: "ThemePanel", dependencies: ["StatusPanel"]),
        .target(name: "AirPodsPanel", dependencies: ["StatusPanel"]),
    ],
    swiftLanguageModes: [.v5]
)
