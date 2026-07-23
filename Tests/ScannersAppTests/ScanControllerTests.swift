import CoreGraphics
import Foundation
import OutputKit
import ScannerKit
import Testing

@testable import ScannersApp

/// Records `ScanController.ocrRunner` invocations so tests can assert it was actually
/// called, and with what language -- thread-safe since the runner closure is `@Sendable`
/// and may be invoked from a detached background task.
private actor OCRCallRecorder {
  private(set) var calls: [(imageWidth: Int, language: String)] = []

  func record(imageWidth: Int, language: String) {
    calls.append((imageWidth, language))
  }
}

// .serialized: every test here spawns its own MainActor-hopping Task and polls it via
// Task.sleep. Left to Swift Testing's default parallel scheduling, several of these
// polling loops competing for the same (single, serial) MainActor executor at once caused
// real timeouts under load, not just slow passes -- serializing this suite removed that
// contention entirely rather than papering over it with a bigger timeout.
@Suite("ScanController", .serialized)
@MainActor
struct ScanControllerTests {
  /// Never touches Vision -- deliberately stricter than DESIGN.md decision #7's "CI tests
  /// must use `.fast`" rule for OCR text tests: these tests exercise the *state machine*
  /// wiring (does a page land, does OCR get invoked with the right language, does the
  /// result get stored), not OCR quality, so there's no reason to pay Vision's cost (or
  /// its CI-hang risk) at all here.
  private func stubOCRRunner(recorder: OCRCallRecorder)
    -> @Sendable (CGImage, String) throws -> [OCRTextLine]
  {
    { image, language in
      let width = image.width
      Task { await recorder.record(imageWidth: width, language: language) }
      return [OCRTextLine(text: "STUB", boundingBox: CGRect(x: 0, y: 0, width: 0.5, height: 0.1))]
    }
  }

  private func waitUntilIdle(_ controller: ScanController, maxAttempts: Int = 500) async {
    var attempts = 0
    while controller.scanState != .idle && attempts < maxAttempts {
      try? await Task.sleep(for: .milliseconds(10))
      attempts += 1
    }
  }

  /// `documentCropper: { $0 }` (identity): like the OCR stub above, these tests exercise
  /// state-machine wiring, not `DocumentCropper`'s own detection quality (that's
  /// `DocumentCropperTests`, in OutputKitTests) -- so no real Vision document-segmentation
  /// call belongs here either.
  private func makeController(
    ocrRunner: @escaping @Sendable (CGImage, String) throws -> [OCRTextLine] = { _, _ in [] }
  ) -> ScanController {
    ScanController(backendMode: .mock, ocrRunner: ocrRunner, documentCropper: { $0 })
  }

  @Test("scan-loop: a .mock scan lands exactly one page in the session")
  func scanLoopAddsOnePage() async throws {
    let session = DocumentSession(documentMode: .image)  // .notNeeded OCR, simpler to assert on
    session.dpi = 100  // full-bed MockSane pixel synthesis is O(pixels); keep tests fast
    let settings = AppSettings(defaults: TestFixtures.isolatedDefaults())
    let controller = makeController()

    controller.scan(into: session, settings: settings)
    await waitUntilIdle(controller)

    #expect(session.pages.count == 1)
    #expect(controller.banner == nil)
    #expect(controller.currentDeviceID == "hp5590:libusb:000:017")
  }

  @Test("scan-loop: a second scan() call while one is in flight is a no-op")
  func concurrentScanCallIsIgnored() async throws {
    let session = DocumentSession(documentMode: .image)
    session.dpi = 100
    let settings = AppSettings(defaults: TestFixtures.isolatedDefaults())
    let controller = makeController()

    controller.scan(into: session, settings: settings)
    controller.scan(into: session, settings: settings)  // should be ignored -- isScanning is true
    await waitUntilIdle(controller)

    #expect(session.pages.count == 1)
  }

  @Test(
    "Text-mode scan kicks off background OCR with the configured language and stores the result")
  func textModeScanRunsBackgroundOCRWithConfiguredLanguage() async throws {
    let session = DocumentSession(documentMode: .text)
    session.dpi = 100
    let settings = AppSettings(defaults: TestFixtures.isolatedDefaults())
    settings.ocrLanguage = "de-DE"
    let recorder = OCRCallRecorder()
    let controller = makeController(ocrRunner: stubOCRRunner(recorder: recorder))

    controller.scan(into: session, settings: settings)
    await waitUntilIdle(controller)

    // Background OCR is a separate detached Task from the scan loop itself -- poll for it
    // to actually land rather than assuming it beat scanState back to .idle.
    var attempts = 0
    while session.pages.first?.ocrStatus == .pending && attempts < 200 {
      try? await Task.sleep(for: .milliseconds(10))
      attempts += 1
    }

    #expect(session.pages.first?.ocrStatus == .done)
    #expect(session.pages.first?.ocrLines?.first?.text == "STUB")

    let calls = await recorder.calls
    #expect(calls.count == 1)
    #expect(calls.first?.language == "de-DE")
  }

  @Test("Image-mode scan never invokes the OCR runner")
  func imageModeScanSkipsOCR() async throws {
    let session = DocumentSession(documentMode: .image)
    session.dpi = 100
    let settings = AppSettings(defaults: TestFixtures.isolatedDefaults())
    let recorder = OCRCallRecorder()
    let controller = makeController(ocrRunner: stubOCRRunner(recorder: recorder))

    controller.scan(into: session, settings: settings)
    await waitUntilIdle(controller)
    // Give a stray background OCR task a chance to appear before asserting none did.
    try? await Task.sleep(for: .milliseconds(50))

    #expect(session.pages.first?.ocrStatus == .notNeeded)
    let calls = await recorder.calls
    #expect(calls.isEmpty)
  }

  @Test("cancelScan() while idle is a safe no-op")
  func cancelWhileIdleIsSafe() {
    let controller = makeController()
    controller.cancelScan()
    #expect(controller.scanState == .idle)
    #expect(controller.banner == nil)
  }

  @Test("scan() immediately followed by cancelScan() always settles back to idle, never hangs")
  func cancelDuringScanSettlesToIdle() async throws {
    let session = DocumentSession(documentMode: .image)
    let settings = AppSettings(defaults: TestFixtures.isolatedDefaults())
    let controller = makeController()

    controller.scan(into: session, settings: settings)
    controller.cancelScan()
    await waitUntilIdle(controller)

    #expect(controller.scanState == .idle)
  }

  @Test("banner mapping: deviceNotFound is retryable")
  func bannerForDeviceNotFound() {
    let banner = ScanController.banner(for: .deviceNotFound("hp5590:libusb:000:099"))
    #expect(banner.isRetryable)
    #expect(banner.message.contains("not found"))
  }

  @Test("banner mapping: deviceBusy is retryable")
  func bannerForDeviceBusy() {
    let banner = ScanController.banner(for: .deviceBusy("hp5590:libusb:000:017"))
    #expect(banner.isRetryable)
    #expect(banner.message.lowercased().contains("busy"))
  }

  @Test("retry() clears the current banner")
  func retryClearsBanner() {
    // ScannerBackendMode.mock's discovery and scan session both talk to a fresh, default-
    // configured MockSane, so there's no way to force a real deviceNotFound/deviceBusy
    // through the public scan(into:settings:) path here -- `banner` is `internal(set)`
    // specifically so this test can set one directly and confirm retry() clears it.
    let controller = makeController()
    controller.banner = ScanController.banner(for: .deviceBusy("hp5590:libusb:000:017"))
    #expect(controller.banner != nil)

    controller.retry()

    #expect(controller.banner == nil)
  }

  // MARK: - Progress throttling (Phase 7, Cell 10 regression)
  //
  // Real hardware finding: a full-bed 1200dpi scan yields ~7,000 raw `.progress` events (one
  // per 64KB SANE read chunk), and mutating `scanState` on every single one flooded
  // SwiftUI's main-thread view-graph badly enough to leave the whole window unresponsive to
  // all input -- including Cancel -- for 8+ minutes. `ProgressPublishPolicy` is the fix; see
  // its doc comment on `ScanController`. Two tests: the policy's own throttling math in
  // isolation (deterministic, no async/timing dependency), then an integration-level check
  // that a real scan with a large, many-chunk `MockSane` frame still behaves correctly
  // end-to-end with the throttle wired in.

  @Test("ProgressPublishPolicy always publishes the very first tick")
  func progressPolicyPublishesFirstTick() {
    var policy = ScanController.ProgressPublishPolicy()
    let published = policy.shouldPublish(0.0)
    #expect(published)
  }

  @Test("ProgressPublishPolicy rejects ticks that haven't advanced by at least 1% yet")
  func progressPolicyRejectsSubThresholdTicks() {
    var policy = ScanController.ProgressPublishPolicy()
    _ = policy.shouldPublish(0.10)
    let halfPercent = policy.shouldPublish(0.105)  // +0.5%, under the 1% minimum step
    let ninetyPercent = policy.shouldPublish(0.109)  // +0.9%, still under
    #expect(!halfPercent)
    #expect(!ninetyPercent)
  }

  @Test("ProgressPublishPolicy publishes once a tick advances by at least 1%")
  func progressPolicyPublishesAtThreshold() {
    var policy = ScanController.ProgressPublishPolicy()
    _ = policy.shouldPublish(0.10)
    let atThreshold = policy.shouldPublish(0.11)  // exactly +1%
    let pastThreshold = policy.shouldPublish(0.13)  // +2% from the new baseline
    #expect(atThreshold)
    #expect(pastThreshold)
  }

  @Test("ProgressPublishPolicy always publishes completion (>= 100%), even mid-step")
  func progressPolicyAlwaysPublishesCompletion() {
    var policy = ScanController.ProgressPublishPolicy()
    _ = policy.shouldPublish(0.995)
    // Only +0.5% from the last published value -- would be rejected by the plain
    // minimum-step rule, but 100% must never be silently dropped (DESIGN: the UI must
    // always be able to show a visible completed state, not get stuck at a stale value).
    let published = policy.shouldPublish(1.0)
    #expect(published)
  }

  @Test(
    "ProgressPublishPolicy bounds published-update count far below raw tick count for a realistic high-frequency stream"
  )
  func progressPolicyBoundsUpdateCountUnderHighFrequencyTicks() {
    var policy = ScanController.ProgressPublishPolicy()
    // Simulates the real 1200dpi-scan shape: ~7,000 raw ticks sweeping smoothly 0...1.
    let rawTickCount = 7_000
    var publishedCount = 0
    for tick in 0...rawTickCount {
      let fraction = Double(tick) / Double(rawTickCount)
      if policy.shouldPublish(fraction) {
        publishedCount += 1
      }
    }
    // At most ~101 possible 1%-steps between 0 and 1 inclusive -- the real regression
    // guard is "nowhere near 1:1 with raw ticks," generous margin above the ~101 ideal to
    // stay robust to rounding at the boundaries.
    #expect(
      publishedCount < 150, "published \(publishedCount) updates for \(rawTickCount) raw ticks")
    #expect(publishedCount < rawTickCount / 10)
  }

  @Test(
    "a real scan with a large, many-chunk MockSane frame still completes correctly with the progress throttle wired in"
  )
  func largeScanCompletesCorrectlyWithProgressThrottle() async throws {
    // 600dpi full-bed gray: ~36MB of synthetic frame data / 64KB read chunks =~560 raw
    // `.progress` ticks through the real ScanSession -> ScanController path (not a
    // simulated stream like the policy-level test above) -- big enough to have actually
    // hit the pre-fix bug's shape, small enough MockSane's O(pixels) synthesis stays fast.
    let session = DocumentSession(documentMode: .image)
    session.dpi = 600
    session.colorMode = .gray
    let settings = AppSettings(defaults: TestFixtures.isolatedDefaults())
    let controller = makeController()

    controller.scan(into: session, settings: settings)
    await waitUntilIdle(controller)

    #expect(session.pages.count == 1)
    #expect(controller.banner == nil)
  }
}
