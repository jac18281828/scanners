// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Vendor/lib holds the dylibs Scripts/build-sane.sh produces (gitignored build
// artifacts — regenerate with that script if missing). Computed as an absolute path
// from this manifest's own location so `swift build`/`swift test`/`swift run` all find
// them via `-rpath` without any DYLD_LIBRARY_PATH env hacks, regardless of the
// invoker's working directory.
let vendorLibDir = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .appendingPathComponent("Vendor/lib")
  .path

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
    .systemLibrary(
      name: "CSane"
    ),
    .target(
      name: "ScannerKit",
      dependencies: ["CSane"],
      swiftSettings: [.swiftLanguageMode(.v6)],
      linkerSettings: [
        .unsafeFlags([
          "-L", vendorLibDir,
          "-Xlinker", "-rpath", "-Xlinker", vendorLibDir,
        ])
      ]
    ),
    .target(
      name: "OutputKit",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .executableTarget(
      name: "scannerkit-cli",
      dependencies: ["ScannerKit"],
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
