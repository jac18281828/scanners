import Testing

@testable import ScannerKit

@Suite("ResolutionPolicy")
struct ResolutionPolicyTests {
  @Test(
    "snaps to the smallest native dpi >= requested",
    arguments: [
      (requested: 100, expected: 100),
      (requested: 75, expected: 100),
      (requested: 150, expected: 200),
      (requested: 200, expected: 200),
      (requested: 250, expected: 300),
      (requested: 300, expected: 300),
      (requested: 450, expected: 600),
      (requested: 600, expected: 600),
      (requested: 1000, expected: 1200),
      (requested: 1200, expected: 1200),
      (requested: 2000, expected: 2400),
      (requested: 2400, expected: 2400),
    ]
  )
  func snapsUpToNearestNative(requested: Int, expected: Int) {
    #expect(ResolutionPolicy.hardwareDPI(for: requested) == expected)
  }

  @Test("requests above the largest native value clamp to it")
  func clampsAboveMax() {
    #expect(ResolutionPolicy.hardwareDPI(for: 4800) == 2400)
    #expect(ResolutionPolicy.hardwareDPI(for: 100_000) == 2400)
  }

  @Test("native set matches the validated hardware facts in DESIGN.md")
  func nativeSetMatchesDesign() {
    #expect(ResolutionPolicy.nativeDPI == [100, 200, 300, 600, 1200, 2400])
  }
}
