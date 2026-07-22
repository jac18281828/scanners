// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Scanners",
  platforms: [
    .macOS(.v14)
  ],
  targets: [
    .executableTarget(
      name: "ScannersApp",
      dependencies: ["ScannerKit", "OutputKit"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "ScannerKit",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "OutputKit",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "ScannerKitTests",
      dependencies: ["ScannerKit"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "OutputKitTests",
      dependencies: ["OutputKit"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ]
)
