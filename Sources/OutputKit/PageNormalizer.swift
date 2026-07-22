import CoreGraphics
import ScannerKit

/// Resamples a `ScannedPage` so its pixel dimensions actually reflect the dpi the user
/// requested, per DESIGN.md decision #3: 75/150dpi are synthetic — the hardware has no
/// native resolution below 100dpi, so `ScanSession` scans at the smallest native dpi `>=
/// requested` and reports both `requestedDPI` and `hardwareDPI` on `ScannedPage`. Every
/// OutputKit output path (`PDFBuilder`, `ImageExporter`) normalizes before touching the
/// image, so a caller can never forget the downscale step.
public enum PageNormalizer {
  /// Downscales `page.image` to match `requestedDPI` when it's below `hardwareDPI`, using a
  /// `CGContext` redraw at `.high` interpolation quality. No-op (returns `page` unchanged,
  /// same `CGImage` instance) when `requestedDPI >= hardwareDPI` — including the clamped
  /// case where a request above the largest native dpi leaves `hardwareDPI < requestedDPI`;
  /// there's nothing to downscale to there, the hardware is already the limiting factor.
  ///
  /// Target pixel dimensions are computed from the page's physical size
  /// (`widthMM`/`heightMM`) and `requestedDPI` directly — not by scaling the hardware pixel
  /// count by a `requestedDPI/hardwareDPI` ratio — so the result matches what a fresh scan
  /// at `requestedDPI` would have produced. (215.889mm width, 100dpi -> 75dpi: physical-mm
  /// basis gives 637px; naive ratio scaling of the 850px hardware image gives 637.5 ->
  /// rounds to 638. Phase-0 hardware observation was 638±1, so both are within tolerance,
  /// but the physical-mm basis is the more principled definition and what's asserted here.)
  public static func normalize(_ page: ScannedPage) -> ScannedPage {
    guard page.requestedDPI < page.hardwareDPI else { return page }

    let targetWidth = targetPixelCount(mm: page.widthMM, dpi: page.requestedDPI)
    let targetHeight = targetPixelCount(mm: page.heightMM, dpi: page.requestedDPI)
    guard targetWidth > 0, targetHeight > 0,
      let resized = resize(page.image, toWidth: targetWidth, toHeight: targetHeight)
    else {
      return page
    }

    return ScannedPage(
      image: resized,
      widthMM: page.widthMM,
      heightMM: page.heightMM,
      requestedDPI: page.requestedDPI,
      hardwareDPI: page.hardwareDPI,
      mode: page.mode
    )
  }

  /// The dpi a (post-`normalize`) page's pixels actually represent, derived from pixel
  /// count and physical size rather than trusted from `requestedDPI`/`hardwareDPI` — so it
  /// stays correct even for the clamped case (`requestedDPI` above the largest native dpi)
  /// where the image was never downscaled and its true density is `hardwareDPI`, not
  /// `requestedDPI`. Used for embedding dpi metadata on exported images.
  public static func effectiveDPI(_ page: ScannedPage) -> Int {
    guard page.widthMM > 0 else { return page.hardwareDPI }
    return Int((Double(page.image.width) / (page.widthMM / 25.4)).rounded())
  }

  private static func targetPixelCount(mm: Double, dpi: Int) -> Int {
    Int((mm / 25.4 * Double(dpi)).rounded())
  }

  private static func resize(
    _ image: CGImage, toWidth width: Int, toHeight height: Int
  ) -> CGImage? {
    let isGray = image.colorSpace?.model == .monochrome
    let colorSpace = isGray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
    let bitmapInfo: UInt32 =
      isGray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue

    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      )
    else {
      return nil
    }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }
}
