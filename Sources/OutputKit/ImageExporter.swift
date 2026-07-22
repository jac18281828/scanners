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

  public static func pngData(for page: ScannedPage) throws -> Data {
    try encode(page, utType: .png, extraProperties: [:])
  }

  public static func tiffData(for page: ScannedPage) throws -> Data {
    try encode(page, utType: .tiff, extraProperties: [:])
  }

  public static func heicData(for page: ScannedPage) throws -> Data {
    try encode(page, utType: .heic, extraProperties: [:])
  }

  private static func encode(
    _ page: ScannedPage, utType: UTType, extraProperties: [CFString: Any]
  ) throws -> Data {
    let normalized = PageNormalizer.normalize(page)
    let dpi = PageNormalizer.effectiveDPI(normalized)

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

    CGImageDestinationAddImage(destination, normalized.image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw ImageExportError.encodingFailed(utType.identifier)
    }
    return data as Data
  }
}
