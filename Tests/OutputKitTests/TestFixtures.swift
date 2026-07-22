import CoreGraphics
import CoreText
import Foundation
import ScannerKit

/// Fixture builders shared across OutputKitTests. Everything here is generated in-process
/// (no committed binary fixtures) — DESIGN.md/Phase 4 explicitly wants golden PDFs avoided
/// and fixture images generated in-test.
enum Fixtures {
  /// Bundles pixel and physical dimensions together, so `solidPage` stays under swiftlint's
  /// parameter-count limit — the same trick `ScannerKit.FrameDecoder`'s `PixelLayout` uses.
  struct PageSize {
    let widthPixels: Int
    let heightPixels: Int
    let widthMM: Double
    let heightMM: Double
  }

  /// A flat-colored `ScannedPage` at the given pixel size, standing in for a real scan.
  /// `hardwareDPI`/`requestedDPI`/the physical mm in `size` are independent knobs so tests
  /// can exercise `PageNormalizer`'s downscale path without needing a real device.
  static func solidPage(
    size: PageSize,
    requestedDPI: Int,
    hardwareDPI: Int,
    mode: ScanMode = .color,
    gray: UInt8 = 200
  ) -> ScannedPage {
    let image = solidImage(
      widthPixels: size.widthPixels, heightPixels: size.heightPixels, mode: mode, gray: gray)
    return ScannedPage(
      image: image,
      widthMM: size.widthMM,
      heightMM: size.heightMM,
      requestedDPI: requestedDPI,
      hardwareDPI: hardwareDPI,
      mode: mode
    )
  }

  static func solidImage(
    widthPixels: Int, heightPixels: Int, mode: ScanMode, gray: UInt8 = 200
  ) -> CGImage {
    switch mode {
    case .color:
      let colorSpace = CGColorSpaceCreateDeviceRGB()
      let context = CGContext(
        data: nil,
        width: widthPixels,
        height: heightPixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      )!
      context.setFillColor(red: 0.7, green: 0.3, blue: 0.2, alpha: 1)
      context.fill(CGRect(x: 0, y: 0, width: widthPixels, height: heightPixels))
      return context.makeImage()!
    case .gray, .blackAndWhite:
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
      context.setFillColor(gray: Double(gray) / 255, alpha: 1)
      context.fill(CGRect(x: 0, y: 0, width: widthPixels, height: heightPixels))
      return context.makeImage()!
    }
  }

  /// Renders `text` onto an 8-bit grayscale page at `dpi`, white background / black text —
  /// a stand-in for a real scanned text document. The canvas is sized from the text's own
  /// measured width (plus margin) so it always fits regardless of string length — a fixed
  /// canvas clipped long fixture strings in an earlier version of this helper, which
  /// silently tanked OCR match scores. When `bilevel` is true, antialiasing is disabled so
  /// the result is a true 0/255 image, the same shape
  /// `ScannerKit.FrameDecoder.decodeLineart1` produces for a real Lineart scan.
  static func textPage(
    _ text: String,
    dpi: Int = 300,
    bilevel: Bool,
    requestedDPI: Int? = nil
  ) -> ScannedPage {
    // ~12pt text on paper, scaled to this dpi — representative of a real scanned document
    // rather than an oversized banner that happens to fill the canvas.
    let fontSize = CGFloat(dpi) * 12.0 / 72.0
    let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
    let fontAttributeKey = NSAttributedString.Key(kCTFontAttributeName as String)
    let colorAttributeKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
    let attributed = NSAttributedString(
      string: text,
      attributes: [
        fontAttributeKey: font,
        colorAttributeKey: CGColor(gray: 0, alpha: 1),
      ]
    )
    let line = CTLineCreateWithAttributedString(attributed)
    let textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))

    let marginPx = fontSize * 1.5
    let width = Int((textWidth + marginPx * 2).rounded(.up))
    let height = Int((fontSize * 3).rounded(.up))
    let widthMM = Double(width) / Double(dpi) * 25.4
    let heightMM = Double(height) / Double(dpi) * 25.4

    let colorSpace = CGColorSpaceCreateDeviceGray()
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    context.setShouldAntialias(!bilevel)
    context.setAllowsAntialiasing(!bilevel)
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    context.textMatrix = .identity
    context.textPosition = CGPoint(x: marginPx, y: fontSize)
    CTLineDraw(line, context)

    let image = context.makeImage()!
    return ScannedPage(
      image: image,
      widthMM: widthMM,
      heightMM: heightMM,
      requestedDPI: requestedDPI ?? dpi,
      hardwareDPI: dpi,
      mode: bilevel ? .blackAndWhite : .gray
    )
  }

  /// A full A4-ish page densely packed with real text (repeated pangrams, ~53 lines at
  /// 11pt/300dpi) — a realistic worst-case stand-in for a scanned text document, used to
  /// give the PDF byte-size ceiling test something non-trivial to compress. A blank or
  /// near-blank fixture would pass that gate trivially regardless of which codec is used.
  static func denseLineartPage(dpi: Int = 300) -> ScannedPage {
    let widthMM = 215.889
    let heightMM = 297.699
    let width = Int((widthMM / 25.4 * Double(dpi)).rounded())
    let height = Int((heightMM / 25.4 * Double(dpi)).rounded())

    let colorSpace = CGColorSpaceCreateDeviceGray()
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    context.setShouldAntialias(false)
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let fontSize = CGFloat(dpi) * 11.0 / 72.0
    let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
    let fontAttributeKey = NSAttributedString.Key(kCTFontAttributeName as String)
    let colorAttributeKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
    let text = String(
      repeating:
        "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs. ",
      count: 3
    )
    let attributed = NSAttributedString(
      string: text,
      attributes: [fontAttributeKey: font, colorAttributeKey: CGColor(gray: 0, alpha: 1)]
    )
    let line = CTLineCreateWithAttributedString(attributed)
    let lineHeight = fontSize * 1.4

    var y = height - Int(lineHeight)
    while y > 100 {
      context.textMatrix = .identity
      context.textPosition = CGPoint(x: 100, y: CGFloat(y))
      CTLineDraw(line, context)
      y -= Int(lineHeight)
    }

    let image = context.makeImage()!
    return ScannedPage(
      image: image,
      widthMM: widthMM,
      heightMM: heightMM,
      requestedDPI: dpi,
      hardwareDPI: dpi,
      mode: .blackAndWhite
    )
  }
}
