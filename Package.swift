// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ClockCore", products: [.library(name: "ClockCore", targets: ["ClockCore"])], targets: [.target(name: "ClockCore"), .testTarget(name: "ClockCoreTests", dependencies: ["ClockCore"])])
