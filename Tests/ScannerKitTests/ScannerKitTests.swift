import Testing

@testable import ScannerKit

@Suite("ScannerKit")
struct ScannerKitTests {
  @Test("version stub is non-empty")
  func versionStubIsNonEmpty() {
    #expect(!ScannerKit.version.isEmpty)
  }
}
