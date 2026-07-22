import CoreGraphics

/// Parameters SANE reported once the scan started — resolved pixel dimensions and both the
/// requested and actual (hardware) dpi, ahead of the pixel data itself.
public struct ScanParametersInfo: Sendable, Equatable {
  public let mode: ScanMode
  public let requestedDPI: Int
  public let hardwareDPI: Int
  public let widthPixels: Int
  public let heightPixels: Int
  public let widthMM: Double
  public let heightMM: Double
}

/// A completed scan: the decoded image plus enough metadata for OutputKit (Phase 4) to lay
/// it out at true physical size and downscale from `hardwareDPI` to `requestedDPI` when
/// they differ (DESIGN.md decision #3 — 75/150dpi are synthetic).
///
/// `CGImage` isn't annotated `Sendable` by Apple, but it's an immutable value once
/// constructed (ScannerKit only ever builds one via `CGImage(...)` and never mutates it
/// afterward) — safe to cross the async boundary here despite the unchecked conformance.
public struct ScannedPage: @unchecked Sendable {
  public let image: CGImage
  public let widthMM: Double
  public let heightMM: Double
  public let requestedDPI: Int
  public let hardwareDPI: Int
  public let mode: ScanMode
}

/// Events published by `ScanSession.scan(config:)`, in order: exactly one `.started`, zero
/// or more `.progress`, then exactly one `.completed` — or the stream throws a `ScanError`
/// instead of ever reaching `.completed`.
public enum ScanEvent: Sendable {
  case started(ScanParametersInfo)
  case progress(Double)
  case completed(ScannedPage)
}
