/// Scan color/bit-depth mode. Maps to SANE's `mode` option string internally —
/// `blackAndWhite` -> `Lineart`, `gray` -> `Gray`, `color` -> `Color` (DESIGN.md decision #4).
public enum ScanMode: String, Sendable, CaseIterable, Equatable {
  case color
  case gray
  case blackAndWhite

  /// The SANE `mode` option value this case negotiates for.
  var saneModeName: String {
    switch self {
    case .color: return "Color"
    case .gray: return "Gray"
    case .blackAndWhite: return "Lineart"
    }
  }
}

/// Paper source. hp5590 exposes more (`ADF Duplex`, `TMA Slides`, `TMA Negatives`, per
/// DESIGN.md) but only flatbed/ADF are in scope for Phase 3.
public enum ScanSource: String, Sendable, CaseIterable, Equatable {
  case flatbed
  case adf

  var saneSourceName: String {
    switch self {
    case .flatbed: return "Flatbed"
    case .adf: return "ADF"
    }
  }
}

/// A scan area in physical millimeters, in the same top-left-origin coordinate space SANE
/// uses (`tl-x`/`tl-y`/`br-x`/`br-y`). `nil` in `ScanConfiguration.area` means "full bed" —
/// `ScanSession` resolves that against the device's own geometry range at scan time, since
/// the bed size is hardware-reported, not hardcoded.
public struct ScanArea: Sendable, Equatable {
  public var topLeftXMM: Double
  public var topLeftYMM: Double
  public var widthMM: Double
  public var heightMM: Double

  public init(topLeftXMM: Double = 0, topLeftYMM: Double = 0, widthMM: Double, heightMM: Double) {
    self.topLeftXMM = topLeftXMM
    self.topLeftYMM = topLeftYMM
    self.widthMM = widthMM
    self.heightMM = heightMM
  }
}

/// What to scan and how. `requestedDPI` is what the caller asked for; `ScanSession`
/// resolves it to a native hardware dpi via `ResolutionPolicy` and reports both back in
/// `ScanEvent.started`/`ScannedPage`.
public struct ScanConfiguration: Sendable, Equatable {
  public var mode: ScanMode
  public var requestedDPI: Int
  public var source: ScanSource
  public var area: ScanArea?

  public init(
    mode: ScanMode, requestedDPI: Int, source: ScanSource = .flatbed, area: ScanArea? = nil
  ) {
    self.mode = mode
    self.requestedDPI = requestedDPI
    self.source = source
    self.area = area
  }
}
