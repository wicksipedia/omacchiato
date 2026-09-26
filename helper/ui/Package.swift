// swift-tools-version:6.0
// Open this package in Xcode to preview the bar's views. A preview fails in
// the root package, because Xcode hosts it in the bar's executable target.
import PackageDescription

let package = Package(
    name: "BarUI",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "StatusGauge", targets: ["StatusGauge"]),
        .library(name: "WeatherPanel", targets: ["WeatherPanel"]),
    ],
    targets: [
        .target(name: "StatusGauge"),
        .target(name: "WeatherPanel"),
    ],
    swiftLanguageModes: [.v5]
)
