// swift-tools-version:6.0
// Open this package in Xcode to preview the gauge. A preview fails in the
// root package, because Xcode hosts it in the bar's executable target.
import PackageDescription

let package = Package(
    name: "StatusGauge",
    platforms: [.macOS("26.0")],
    products: [.library(name: "StatusGauge", targets: ["StatusGauge"])],
    targets: [.target(name: "StatusGauge")],
    swiftLanguageModes: [.v5]
)
