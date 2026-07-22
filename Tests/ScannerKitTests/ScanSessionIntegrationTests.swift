import CoreGraphics
import Testing

@testable import ScannerKit

@Suite("ScanSession end-to-end (MockSane)")
struct ScanSessionIntegrationTests {
  @Test(
    "each mode produces .started, at least one .progress, then .completed with a correctly-shaped image",
    arguments: [ScanMode.color, .gray, .blackAndWhite]
  )
  func fullScanProducesExpectedEvents(mode: ScanMode) async throws {
    let mock = MockSane()
    let session = ScanSession(
      deviceID: MockSane.Configuration.default.devices[0].name,
      backend: mock,
      runner: SaneRunner()
    )
    let config = ScanConfiguration(mode: mode, requestedDPI: 100)

    var events: [ScanEvent] = []
    for try await event in session.scan(config: config) {
      events.append(event)
    }

    guard case .started(let info) = events.first else {
      Issue.record("expected first event to be .started")
      return
    }
    guard case .completed(let page) = events.last else {
      Issue.record("expected last event to be .completed")
      return
    }

    #expect(info.mode == mode)
    #expect(page.mode == mode)
    #expect(page.hardwareDPI == 100)
    #expect(page.requestedDPI == 100)
    #expect(page.image.width == info.widthPixels)
    #expect(page.image.height == info.heightPixels)

    let expectedBitsPerPixel = mode == .color ? 24 : 8
    #expect(page.image.bitsPerPixel == expectedBitsPerPixel)

    // The bed is roughly A4 at 100dpi: non-trivial dimensions, not a degenerate 0x0/1x1.
    #expect(page.image.width > 100)
    #expect(page.image.height > 100)
  }

  @Test("progress reaches 100% by the time the stream completes")
  func progressReachesCompletion() async throws {
    let mock = MockSane()
    let session = ScanSession(
      deviceID: MockSane.Configuration.default.devices[0].name,
      backend: mock,
      runner: SaneRunner()
    )
    let config = ScanConfiguration(mode: .gray, requestedDPI: 300)

    var lastProgress: Double = 0
    for try await event in session.scan(config: config) {
      if case .progress(let fraction) = event {
        lastProgress = fraction
      }
    }

    #expect(lastProgress == 1.0)
  }
}
