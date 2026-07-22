/// The HP 4570c's native hardware resolutions (validated on real hardware — see
/// DESIGN.md). A requested dpi that isn't in this set gets scanned at the smallest native
/// dpi that is `>= requested`, and OutputKit (Phase 4) downscales from there so page output
/// still reflects the dpi the user actually asked for.
public enum ResolutionPolicy {
  /// Native resolutions in ascending order. Public so UI (Phase 5) can build a picker
  /// without duplicating this list.
  public static let nativeDPI: [Int] = [100, 200, 300, 600, 1200, 2400]

  /// The native dpi ScannerKit will actually drive the hardware at for a given request.
  /// Requests above the largest native value clamp to that value — there's no higher
  /// resolution to snap up to.
  public static func hardwareDPI(for requested: Int) -> Int {
    nativeDPI.first(where: { $0 >= requested }) ?? nativeDPI[nativeDPI.count - 1]
  }
}
