import CoreGraphics
import Foundation
import ImageIO
import ScannerKit
import UniformTypeIdentifiers

public enum ImageExportError: Error, CustomStringConvertible, Sendable {
  case encodingFailed(String)

  public var description: String {
    switch self {
    case .encodingFailed(let format): return "failed to encode image as \(format)"
    }
  }
}

/// Exports a single `ScannedPage` to a standalone image file via ImageIO. The page is
/// normalized (`PageNormalizer`) first, and dpi metadata (`kCGImagePropertyDPIWidth`/
/// `DPIHeight`) is embedded from the normalized pixel/physical-size ratio — verify with
/// `sips -g dpiWidth <file>`.
public enum ImageExporter {
  public static let defaultJPEGQuality: Double = 0.85

  public static func jpegData(
    for page: ScannedPage, quality: Double = defaultJPEGQuality
  ) throws -> Data {
    try encode(
      page, utType: .jpeg, extraProperties: [kCGImageDestinationLossyCompressionQuality: quality])
  }

  /// PNG natively supports 1-bit-per-pixel storage, so a `.blackAndWhite` page is packed via
  /// `LineartPacker` before encoding -- the same lossless repack `PDFBuilder` already applies
  /// for Lineart pages, just for a standalone file instead of a PDF stream. Content is already
  /// bilevel (`FrameDecoder.decodeLineart1`), so this loses nothing; it only drops the ~8x
  /// waste of storing two-valued samples at 8 bits each.
  public static func pngData(for page: ScannedPage) throws -> Data {
    try encode(page, utType: .png, extraProperties: [:], pack1BitLineart: true)
  }

  /// See `pngData` -- TIFF also natively supports 1-bit-per-pixel storage.
  public static func tiffData(for page: ScannedPage) throws -> Data {
    try encode(page, utType: .tiff, extraProperties: [:], pack1BitLineart: true)
  }

  /// JPEG and HEIC are lossy codecs with no bilevel/1-bit encoding mode -- packing first would
  /// buy nothing (the encoder re-expands to its own internal precision regardless) and risks
  /// compounding quantization, so these stay at the normalized 8-bit image.
  public static func heicData(for page: ScannedPage) throws -> Data {
    try encode(page, utType: .heic, extraProperties: [:])
  }

  private static func encode(
    _ page: ScannedPage, utType: UTType, extraProperties: [CFString: Any],
    pack1BitLineart: Bool = false
  ) throws -> Data {
    let normalized = PageNormalizer.normalize(page)
    let dpi = PageNormalizer.effectiveDPI(normalized)
    let image =
      pack1BitLineart && normalized.mode == .blackAndWhite
      ? (LineartPacker.pack1Bit(normalized.image) ?? normalized.image)
      : normalized.image

    guard let data = CFDataCreateMutable(nil, 0) else {
      throw ImageExportError.encodingFailed(utType.identifier)
    }
    guard
      let destination = CGImageDestinationCreateWithData(
        data, utType.identifier as CFString, 1, nil)
    else {
      throw ImageExportError.encodingFailed(utType.identifier)
    }

    var properties: [CFString: Any] = [
      kCGImagePropertyDPIWidth: Double(dpi),
      kCGImagePropertyDPIHeight: Double(dpi),
    ]
    for (key, value) in extraProperties {
      properties[key] = value
    }

    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw ImageExportError.encodingFailed(utType.identifier)
    }
    return data as Data
  }
}
