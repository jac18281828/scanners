import Foundation
import OutputKit
import ScannerKit
import UniformTypeIdentifiers

/// Standalone image export formats for the Image flow's "Save Image…" panel. DESIGN.md:
/// "JPEG default; PNG, TIFF, HEIC options."
public enum ImageFormat: String, CaseIterable, Codable, Sendable, Identifiable {
  case jpeg
  case png
  case tiff
  case heic

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .jpeg: return "JPEG"
    case .png: return "PNG"
    case .tiff: return "TIFF"
    case .heic: return "HEIC"
    }
  }

  public var fileExtension: String {
    switch self {
    case .jpeg: return "jpg"
    case .png: return "png"
    case .tiff: return "tiff"
    case .heic: return "heic"
    }
  }

  public var utType: UTType {
    switch self {
    case .jpeg: return .jpeg
    case .png: return .png
    case .tiff: return .tiff
    case .heic: return .heic
    }
  }

  /// Encodes `page` via the matching `OutputKit.ImageExporter` entry point.
  public func encode(_ page: ScannedPage) throws -> Data {
    switch self {
    case .jpeg: return try ImageExporter.jpegData(for: page)
    case .png: return try ImageExporter.pngData(for: page)
    case .tiff: return try ImageExporter.tiffData(for: page)
    case .heic: return try ImageExporter.heicData(for: page)
    }
  }
}
