import CoreGraphics
import CoreText
import Foundation
import ImageIO
import ScannerKit
import UniformTypeIdentifiers

public enum PDFBuilderError: Error, CustomStringConvertible, Sendable {
  case contextCreationFailed
  case imageEncodingFailed
  case pageDrawFailed

  public var description: String {
    switch self {
    case .contextCreationFailed: return "failed to create a CGContext PDF consumer"
    case .imageEncodingFailed: return "failed to encode page image for PDF embedding"
    case .pageDrawFailed: return "failed to draw page into PDF context"
    }
  }
}

/// Assembles a multi-page PDF from `ScannedPage`s via a CGContext PDF (not PDFKit — PDFKit
/// can't draw invisible OCR text, only CoreGraphics can — DESIGN.md decision #5).
///
/// Each page's media box comes from the page's own physical size in mm (1pt = 1/72in), so
/// pages print true-size on paper regardless of what dpi they were scanned/normalized at.
/// One `PDFBuilder` builds one document: construct, `append` every page in order, `finish`
/// once to get the bytes.
public final class PDFBuilder {
  private static let mmPerInch = 25.4
  private static let pointsPerInch = 72.0
  /// JPEG quality for color/gray page images embedded in the PDF. Matches
  /// `ImageExporter`'s default so a page looks the same whether it ends up in a PDF or a
  /// standalone JPEG.
  private static let jpegQuality: CGFloat = 0.85

  private let mutableData: CFMutableData
  private var context: CGContext?
  private var finished = false

  public private(set) var pageCount = 0

  public init() throws {
    guard let data = CFDataCreateMutable(nil, 0) else {
      throw PDFBuilderError.contextCreationFailed
    }
    mutableData = data
    guard let consumer = CGDataConsumer(data: mutableData) else {
      throw PDFBuilderError.contextCreationFailed
    }
    var defaultMediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(consumer: consumer, mediaBox: &defaultMediaBox, nil) else {
      throw PDFBuilderError.contextCreationFailed
    }
    self.context = context
  }

  /// Appends one page. The page image is normalized (`PageNormalizer`) before embedding, so
  /// output pixel density always matches `page.requestedDPI`. Pass `includeOCRTextLayer:
  /// true` for text-mode pages (DESIGN.md's "Text" product mode) to run Vision OCR and draw
  /// recognized lines in invisible text mode over the image, at their own bounding boxes —
  /// searchable/selectable in Preview.app without changing what's visible.
  ///
  /// `ocrLanguage` forwards to `OCREngine.recognizeLines` — see its doc comment
  /// (DESIGN.md decision #6) for why OCR is pinned to a fixed language rather than using
  /// Vision's automatic language detection.
  public func append(
    page: ScannedPage,
    includeOCRTextLayer: Bool = false,
    ocrLanguage: String = "en-US"
  ) throws {
    guard let context, !finished else {
      throw PDFBuilderError.contextCreationFailed
    }

    let normalized = PageNormalizer.normalize(page)
    let widthPt = normalized.widthMM / Self.mmPerInch * Self.pointsPerInch
    let heightPt = normalized.heightMM / Self.mmPerInch * Self.pointsPerInch
    var mediaBox = CGRect(x: 0, y: 0, width: widthPt, height: heightPt)

    let pageInfo: CFDictionary =
      [
        kCGPDFContextMediaBox as String: NSData(
          bytes: &mediaBox, length: MemoryLayout<CGRect>.size)
      ] as CFDictionary

    context.beginPDFPage(pageInfo)

    let embeddedImage = try compressedImage(for: normalized)
    context.draw(embeddedImage, in: CGRect(x: 0, y: 0, width: widthPt, height: heightPt))

    if includeOCRTextLayer {
      let lines = try OCREngine.recognizeLines(in: normalized.image, language: ocrLanguage)
      drawInvisibleText(lines, context: context, pageWidthPt: widthPt, pageHeightPt: heightPt)
    }

    context.endPDFPage()
    pageCount += 1
  }

  /// Finalizes the document and returns its bytes. Core Graphics writes the PDF trailer
  /// when the context is released, so this drops the last strong reference to it before
  /// reading `mutableData` back out. Calling `append` after `finish` throws.
  public func finish() -> Data {
    context = nil
    finished = true
    return mutableData as Data
  }

  // MARK: - Image compression

  /// Re-encodes the page image so Quartz's PDF writer has the best chance of embedding a
  /// compressed stream instead of raw/Flate pixels:
  /// - Color/gray: pre-encode to JPEG via ImageIO, then decode that JPEG data back to a
  ///   `CGImage`. Drawing an image that Quartz recognizes as JPEG-backed makes it embed the
  ///   original DCTDecode stream rather than re-flating the pixels (verified by inspecting
  ///   the emitted PDF's filter names — see Scripts/smoke-output.sh).
  /// - Lineart (`.blackAndWhite`): repack to true 1-bit-per-pixel (`LineartPacker`) so
  ///   Quartz can CCITTFaxDecode-compress it; FrameDecoder's 8-bit expansion never
  ///   compresses well because it isn't actually 1bpp. Falls back to drawing the 8-bit
  ///   image (Flate) if packing fails for any reason — see the phase escalation note.
  private func compressedImage(for page: ScannedPage) throws -> CGImage {
    switch page.mode {
    case .blackAndWhite:
      return LineartPacker.pack1Bit(page.image) ?? page.image
    case .color, .gray:
      return try jpegBackedImage(page.image)
    }
  }

  private func jpegBackedImage(_ image: CGImage) throws -> CGImage {
    guard let data = CFDataCreateMutable(nil, 0) else {
      throw PDFBuilderError.imageEncodingFailed
    }
    guard
      let destination = CGImageDestinationCreateWithData(
        data, UTType.jpeg.identifier as CFString, 1, nil)
    else {
      throw PDFBuilderError.imageEncodingFailed
    }
    let options =
      [kCGImageDestinationLossyCompressionQuality as String: Self.jpegQuality] as CFDictionary
    CGImageDestinationAddImage(destination, image, options)
    guard CGImageDestinationFinalize(destination) else {
      throw PDFBuilderError.imageEncodingFailed
    }
    guard let source = CGImageSourceCreateWithData(data, nil),
      let jpegImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw PDFBuilderError.imageEncodingFailed
    }
    return jpegImage
  }

  // MARK: - OCR text layer

  /// Fraction of the recognized box height used as the synthetic font's point size —
  /// roughly a font's cap-height-to-em ratio, so the invisible glyphs' actual ink stays
  /// close to the box Vision reported rather than badly overshooting it.
  private static let fontSizeToBoxHeightRatio: CGFloat = 0.9

  private func drawInvisibleText(
    _ lines: [OCRTextLine], context: CGContext, pageWidthPt: CGFloat, pageHeightPt: CGFloat
  ) {
    for line in lines where !line.text.isEmpty {
      let box = line.boundingBox
      let boxOriginPt = CGPoint(x: box.origin.x * pageWidthPt, y: box.origin.y * pageHeightPt)
      let boxSizePt = CGSize(width: box.width * pageWidthPt, height: box.height * pageHeightPt)
      guard boxSizePt.width > 0, boxSizePt.height > 0 else { continue }

      let fontSize = boxSizePt.height * Self.fontSizeToBoxHeightRatio
      let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
      // CTFont, not NSFont — use CoreText's own attribute key rather than
      // NSAttributedString.Key.font (an AppKit/UIKit addition expecting NSFont/UIFont).
      let fontAttributeKey = NSAttributedString.Key(kCTFontAttributeName as String)
      let attributed = NSAttributedString(string: line.text, attributes: [fontAttributeKey: font])
      let ctLine = CTLineCreateWithAttributedString(attributed)
      let lineWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
      let horizontalScale = lineWidth > 0 ? boxSizePt.width / lineWidth : 1

      context.saveGState()
      context.setTextDrawingMode(.invisible)
      // Vision's boundingBox origin is the box's bottom-left corner, matching a raw
      // (non-flipped) CGContext's own bottom-left-origin coordinate space directly — no
      // y-flip needed here (see OCRTextLine's doc comment). Translation goes through
      // textPosition, not textMatrix's own tx/ty — CoreText positions glyphs from
      // textPosition and only uses textMatrix for scale/rotation/skew.
      context.textMatrix = CGAffineTransform(scaleX: horizontalScale, y: 1)
      context.textPosition = boxOriginPt
      CTLineDraw(ctLine, context)
      context.restoreGState()
    }
  }
}
