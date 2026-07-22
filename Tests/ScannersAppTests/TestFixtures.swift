import CoreGraphics
import Foundation
import ScannerKit

/// Minimal in-process `ScannedPage` fixtures for ScannersAppTests — a smaller, local twin
/// of `OutputKitTests`' `Fixtures` (different test target, no cross-target sharing in
/// SwiftPM without a shared library target, and this suite only needs a solid page, not
/// OutputKit's text-rendering fixtures).
enum TestFixtures {
  static func solidPage(
    widthPixels: Int = 100,
    heightPixels: Int = 140,
    widthMM: Double = 25.4,
    heightMM: Double = 35.56,
    mode: ScanMode = .gray,
    requestedDPI: Int = 100,
    hardwareDPI: Int = 100
  ) -> ScannedPage {
    let colorSpace = CGColorSpaceCreateDeviceGray()
    let context = CGContext(
      data: nil,
      width: widthPixels,
      height: heightPixels,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    context.setFillColor(gray: 0.5, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: widthPixels, height: heightPixels))
    let image = context.makeImage()!
    return ScannedPage(
      image: image,
      widthMM: widthMM,
      heightMM: heightMM,
      requestedDPI: requestedDPI,
      hardwareDPI: hardwareDPI,
      mode: mode
    )
  }

  /// A `UserDefaults` suite isolated to one test, so `AppSettings` persistence tests never
  /// touch the real `.standard` defaults (which the dev/manual-test app itself uses) and
  /// never interfere with each other when run concurrently.
  static func isolatedDefaults(name: String = #function) -> UserDefaults {
    let suiteName = "dev.scanners.tests.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}
