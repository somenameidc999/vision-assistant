// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "VisionCore",
    platforms: [.iOS("16.6"), .macOS(.v15)],
    products: [.library(name: "VisionCore", targets: ["VisionCore"])],
    targets: [.target(name: "VisionCore"), .testTarget(name: "VisionCoreTests", dependencies: ["VisionCore"])]
)
