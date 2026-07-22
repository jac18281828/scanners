import Foundation
import ScannerKit

/// One click applies mode+dpi+color(+image format) — DESIGN.md's "Settings: presets, not
/// forms." Built-ins ship with fixed ids so they're recognizable/de-duplicatable across
/// launches even after `AppSettings` round-trips them through UserDefaults; users can
/// rename, delete, or reorder any preset (including built-ins) the same way.
public struct ScanPreset: Identifiable, Equatable, Sendable {
  public var id: UUID
  public var name: String
  public var documentMode: DocumentMode
  public var dpi: Int
  public var colorMode: ScanMode
  /// Only meaningful when `documentMode == .image` — the Text/PDF flow always saves PDF.
  public var imageFormat: ImageFormat

  public init(
    id: UUID = UUID(),
    name: String,
    documentMode: DocumentMode,
    dpi: Int,
    colorMode: ScanMode,
    imageFormat: ImageFormat = .jpeg
  ) {
    self.id = id
    self.name = name
    self.documentMode = documentMode
    self.dpi = dpi
    self.colorMode = colorMode
    self.imageFormat = imageFormat
  }
}

// Manual Codable: `ScannerKit.ScanMode` itself isn't `Codable` (a Phase 3 type this phase
// builds on rather than modifies for a single call site), so `colorMode` round-trips
// through its own `rawValue` string here instead of widening ScannerKit's public surface
// for it.
extension ScanPreset: Codable {
  private enum CodingKeys: String, CodingKey {
    case id, name, documentMode, dpi, colorMode, imageFormat
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    documentMode = try container.decode(DocumentMode.self, forKey: .documentMode)
    dpi = try container.decode(Int.self, forKey: .dpi)
    imageFormat = try container.decode(ImageFormat.self, forKey: .imageFormat)
    let colorModeRaw = try container.decode(String.self, forKey: .colorMode)
    guard let decodedColorMode = ScanMode(rawValue: colorModeRaw) else {
      throw DecodingError.dataCorruptedError(
        forKey: .colorMode, in: container, debugDescription: "unknown ScanMode '\(colorModeRaw)'")
    }
    colorMode = decodedColorMode
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(documentMode, forKey: .documentMode)
    try container.encode(dpi, forKey: .dpi)
    try container.encode(imageFormat, forKey: .imageFormat)
    try container.encode(colorMode.rawValue, forKey: .colorMode)
  }
}

extension ScanPreset {
  // Fixed UUIDs so the same three built-ins remain identifiable (for de-dup / "is this a
  // built-in" checks) across every launch and every persistence round-trip.
  private static let textDocID = UUID(uuidString: "8A5B0001-0000-4000-8000-000000000001")!
  private static let photoID = UUID(uuidString: "8A5B0001-0000-4000-8000-000000000002")!
  private static let archiveID = UUID(uuidString: "8A5B0001-0000-4000-8000-000000000003")!

  /// DESIGN.md: "text/300/B&W/PDF".
  public static let textDoc = ScanPreset(
    id: textDocID, name: "Text Doc", documentMode: .text, dpi: 300, colorMode: .blackAndWhite)

  /// DESIGN.md: "image/600/color/JPEG".
  public static let photo = ScanPreset(
    id: photoID, name: "Photo", documentMode: .image, dpi: 600, colorMode: .color,
    imageFormat: .jpeg)

  /// DESIGN.md: "image/2400/color/TIFF".
  public static let archive = ScanPreset(
    id: archiveID, name: "Archive", documentMode: .image, dpi: 2400, colorMode: .color,
    imageFormat: .tiff)

  public static let builtIns: [ScanPreset] = [.textDoc, .photo, .archive]
}
