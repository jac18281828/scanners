import ScannerKit

/// The product-level "Text | Image" toggle from DESIGN.md's control strip — distinct from
/// `ScannerKit.ScanMode` (color/gray/blackAndWhite), which is the *color* half of the
/// control strip's two pickers. Each `DocumentMode` has its own dpi option set and default
/// color, per DESIGN.md's product-behavior section.
public enum DocumentMode: String, CaseIterable, Codable, Sendable, Equatable, Identifiable {
  case text
  case image

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .text: return "Text"
    case .image: return "Image"
    }
  }

  /// DESIGN.md: "Text: 75/150/300/600... Image: 300/600/1200/2400."
  public var dpiOptions: [Int] {
    switch self {
    case .text: return [75, 150, 300, 600]
    case .image: return [300, 600, 1200, 2400]
    }
  }

  public var defaultDPI: Int {
    switch self {
    case .text: return 300
    case .image: return 600
    }
  }

  /// DESIGN.md's product-behavior section only names two *default* color states ("default
  /// 300 B&W; also color" / "default 600 Color; also B&W") — `.gray` was originally left off
  /// the control strip's color picker entirely as a UI-detail deviation. It's a real hardware
  /// mode the scanner reports (DESIGN.md's "Validated hardware facts": `Color`, `Color (48
  /// bits)`, `Gray`, `Lineart`) and a real escape hatch from Lineart's hardware bilevel
  /// threshold (see `DocumentCropper+ContentExtent.swift`'s and `ImageExporter`'s doc
  /// comments on why Lineart can lose saturated color content it shouldn't), so it's exposed
  /// as a manual third choice -- neither mode defaults to it.
  public var defaultColorMode: ScanMode {
    switch self {
    case .text: return .blackAndWhite
    case .image: return .color
    }
  }

  /// The color picker's option set for this mode.
  public static let colorOptions: [ScanMode] = [.color, .gray, .blackAndWhite]
}
