/// Marker type for the OutputKit module.
///
/// OutputKit is pure — `CGImage` in, bytes out. It consumes `ScannerKit.ScannedPage` and
/// produces PDF/image `Data`; no target here ever touches SANE or the scanner hardware.
public enum OutputKit {
  /// Package version stub, replaced with real versioning once tags exist.
  public static let version = "0.0.0"
}
