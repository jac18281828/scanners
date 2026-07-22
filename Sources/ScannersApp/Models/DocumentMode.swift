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

  /// DESIGN.md names only two color states in the product-behavior section ("default 300
  /// B&W; also color" / "default 600 Color; also B&W") — `ScanMode.gray` is never mentioned
  /// there and isn't exposed by the control strip's color picker (see the phase report's
  /// deviations for this UI-detail decision).
  public var defaultColorMode: ScanMode {
    switch self {
    case .text: return .blackAndWhite
    case .image: return .color
    }
  }

  /// The color picker's two-way option set for this mode.
  public static let colorOptions: [ScanMode] = [.color, .blackAndWhite]
}
