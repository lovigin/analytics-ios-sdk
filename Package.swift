// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LoviginAnalytics",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "LoviginAnalytics", targets: ["LoviginAnalytics"])],
    targets: [
        .target(name: "LoviginAnalytics", resources: [.process("PrivacyInfo.xcprivacy")]),
        .testTarget(name: "LoviginAnalyticsTests", dependencies: ["LoviginAnalytics"])
    ]
)
