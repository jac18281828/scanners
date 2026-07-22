import Foundation
import Testing

@testable import ScannerKit

/// Lets the test's outer scope observe, from outside the consuming `Task`, that the
/// `.started` event has actually been delivered — used to replace a blind fixed-duration
/// sleep (flaky under CI scheduling latency; see `cancellingConsumerInvokesBackendCancel`)
/// with a bounded poll for the real condition instead of a guessed time window.
private actor StartedFlag {
  private(set) var value = false
  func markStarted() { value = true }
}

@Suite("Cancellation")
struct CancellationTests {
  @Test("cancelling the consuming task wires through to backend.cancel and stops the stream")
  func cancellingConsumerInvokesBackendCancel() async throws {
    // A modest scan area keeps MockSane's own (synchronous, non-cancellable) frame
    // synthesis in `start()` fast, while a small artificial per-read delay still forces
    // several `sane_read`-equivalent calls at 64KB/chunk — enough real iterations to give
    // a reliable window to cancel mid-scan rather than racing a scan that either finishes
    // instantly or spends hundreds of ms generating test data before the loop even starts.
    var configuration = MockSane.Configuration.default
    configuration.readDelay = 0.01
    let mock = MockSane(configuration: configuration)
    let session = ScanSession(
      deviceID: configuration.devices[0].name,
      backend: mock,
      runner: SaneRunner()
    )
    let config = ScanConfiguration(
      mode: .color,
      requestedDPI: 600,
      area: ScanArea(widthMM: 20, heightMM: 20)
    )

    let startedFlag = StartedFlag()
    let consumer = Task<Bool, Never> {
      var sawStarted = false
      do {
        for try await event in session.scan(config: config) {
          if case .started = event {
            sawStarted = true
            await startedFlag.markStarted()
          }
        }
      } catch {
        // Cancellation surfaces as an error (ScanError.cancelled or CancellationError,
        // depending on exactly where the race lands) — either is expected here.
      }
      return sawStarted
    }

    // Poll for the real condition (.started actually delivered) instead of guessing a
    // fixed sleep duration long enough to cover it — a blind sleep here previously flaked
    // under CI's higher/less predictable scheduling latency (observed passing locally in
    // 0.37s but timing out this exact window on a GitHub Actions runner).
    var startedAttempts = 0
    while await !startedFlag.value && startedAttempts < 200 {
      try await Task.sleep(for: .milliseconds(10))
      startedAttempts += 1
    }

    consumer.cancel()
    let sawStarted = await consumer.value

    // `consumer.value` only guarantees the *consuming* for-await loop stopped (it can
    // return as soon as its own task notices cancellation) — it says nothing about
    // whether the producer-side inner task has run its `backend.cancel()`/`close()`
    // cleanup on the SaneRunner queue yet. Poll briefly for that to land instead of
    // assuming it already has.
    var attempts = 0
    while mock.cancelCallCount == 0 && attempts < 50 {
      try await Task.sleep(for: .milliseconds(10))
      attempts += 1
    }

    #expect(sawStarted)
    #expect(mock.cancelCallCount > 0)
  }

  @Test("a scan that completes before cancellation never calls backend.cancel")
  func completedScanDoesNotCallCancel() async throws {
    let mock = MockSane()
    let session = ScanSession(
      deviceID: MockSane.Configuration.default.devices[0].name,
      backend: mock,
      runner: SaneRunner()
    )
    let config = ScanConfiguration(mode: .gray, requestedDPI: 100)

    for try await _ in session.scan(config: config) {}

    #expect(mock.cancelCallCount == 0)
  }
}
