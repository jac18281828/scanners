import Testing

@testable import OutputKit

@Suite("OutputKit")
struct OutputKitTests {
  @Test("version stub is non-empty")
  func versionStubIsNonEmpty() {
    #expect(!OutputKit.version.isEmpty)
  }
}
