import CoreGraphics
import Foundation
import Observation
import OutputKit
import ScannerKit
import Vision

/// Drives one scan at a time against ScannerKit and reports state a view can render
/// directly: idle/discovering/scanning(progress), plus a non-modal banner for
/// unplugged/busy (DESIGN.md: "non-modal inline banner with Retry ... never a blocking
/// alert loop"). All ScannerKit access goes through the public API only —
/// `ScannerDiscovery`/`ScanSession`'s `mode:` initializers (`ScannerBackendMode`), never the
/// internal `SaneBackend`/`MockSane` types.
@MainActor
@Observable
public final class ScanController {
  public enum ScanState: Equatable {
    case idle
    case discovering
    case scanning(progress: Double)
  }

  public struct Banner: Equatable, Sendable {
    public var message: String
    public var isRetryable: Bool
  }

  /// Bounds how often raw `ScanEvent.progress` ticks actually mutate `scanState`. A
  /// full-bed high-dpi scan can yield thousands of `.progress` events -- one per 64KB SANE
  /// read chunk (`ScanSession.readChunkSize`); at 1200dpi full-bed color that's ~7,000
  /// ticks, at 2400dpi ~27,000+. Mutating this `@Observable` class's `scanState` on every
  /// single one floods SwiftUI's main-thread view-graph with a re-render per tick. Found on
  /// real hardware (Phase 7, Cell 10): a 1200dpi scan left the whole window unresponsive to
  /// all input -- including clicking Cancel -- for 8+ minutes; `sample` showed the main
  /// thread pegged at ~100% CPU inside SwiftUI's `AttributeGraph`/`GraphHost` render
  /// machinery the entire time, with RSS nearly flat (not scan I/O). `ProgressPublishPolicy`
  /// only lets a `.progress` tick through if it moves the fraction by at least 1% since the
  /// last one actually published (plus always the first tick and anything at/above 100%),
  /// bounding renders to roughly 100 per scan regardless of how many raw chunks the backend
  /// reports -- see the "Progress throttling" section of `ScanControllerTests` for both the
  /// throttling behavior itself in isolation (deterministic, no timing/hardware dependency)
  /// and a `ScanController`-level integration regression against a real, large, many-chunk
  /// `MockSane` scan.
  struct ProgressPublishPolicy {
    static let minimumStep: Double = 0.01
    // Binary floating point: e.g. 0.11 - 0.10 == 0.009999999999999998, just under
    // minimumStep, so an exact-looking 1% step would otherwise be wrongly rejected at the
    // boundary. Real progress fractions (arbitrary byte-count ratios) rarely land exactly
    // on a 1% line anyway; this only guards the boundary case, it doesn't loosen the policy.
    private static let epsilon: Double = 1e-9
    private var lastPublished: Double?

    /// Returns whether `fraction` should be published (and records it as the new baseline
    /// if so) -- always `true` for the very first call, for anything at/above 100%
    /// (guarantees the UI always shows a visible completion state, never gets stuck at a
    /// stale sub-100% value if the last few ticks got coalesced away), and otherwise only
    /// once `fraction` has advanced by `minimumStep` since the last published value.
    mutating func shouldPublish(_ fraction: Double) -> Bool {
      guard let lastPublished else {
        self.lastPublished = fraction
        return true
      }
      guard fraction >= 1.0 || fraction - lastPublished >= Self.minimumStep - Self.epsilon else {
        return false
      }
      self.lastPublished = fraction
      return true
    }
  }

  public private(set) var scanState: ScanState = .idle
  // `internal(set)`, not `private(set)`: real app code only ever reads this from outside
  // the type, but `@testable import` needs to set it directly to exercise `retry()`
  // clearing a banner without needing a genuinely-broken mock device to produce one.
  public internal(set) var banner: Banner?
  public private(set) var currentDeviceID: String?

  public let backendMode: ScannerBackendMode
  private let discovery: ScannerDiscovery
  private var scanTask: Task<Void, Never>?

  /// Runs OCR for one page's normalized image. Defaults to the real `OCREngine` at the
  /// shipped app's `.accurate` level (DESIGN.md decision #7) — tests inject a stub so unit
  /// tests of the state machine never invoke Vision at all (stricter than the CI-hygiene
  /// rule of merely using `.fast`; see the phase report).
  public var ocrRunner: @Sendable (CGImage, String) throws -> [OCRTextLine]

  /// Auto-crops a just-scanned page to its detected document boundary (DESIGN.md decision
  /// #9). Defaults to the real `DocumentCropper.crop` — tests inject the identity function
  /// so unit tests of the state machine never invoke Vision's document-segmentation model
  /// either, same rationale as `ocrRunner`.
  public var documentCropper: @Sendable (ScannedPage) -> ScannedPage

  public init(
    backendMode: ScannerBackendMode,
    ocrRunner: @escaping @Sendable (CGImage, String) throws -> [OCRTextLine] = { image, language in
      try OCREngine.recognizeLines(in: image, language: language, recognitionLevel: .accurate)
    },
    documentCropper: @escaping @Sendable (ScannedPage) -> ScannedPage = DocumentCropper.crop
  ) {
    self.backendMode = backendMode
    self.discovery = ScannerDiscovery(mode: backendMode)
    self.ocrRunner = ocrRunner
    self.documentCropper = documentCropper
  }

  public var isScanning: Bool {
    if case .idle = scanState { return false }
    return true
  }

  /// Starts a scan into `session` using `session`'s current mode/dpi/color and `settings`'
  /// source/lamp-timeout/OCR-language. No-op if a scan is already in flight.
  public func scan(into session: DocumentSession, settings: AppSettings) {
    guard !isScanning else { return }
    banner = nil
    // Set synchronously, not inside runScan's Task body: `isScanning`/`scanState` must
    // already read as non-idle the instant this call returns, both so the immediate
    // `guard !isScanning` re-entrancy check above is race-free against a second call
    // issued right after this one, and so a caller polling for "no longer idle" (e.g.
    // ScanControllerTests) can't observe a false-idle window before the Task gets
    // scheduled.
    scanState = .discovering
    scanTask = Task { [weak self] in
      await self?.runScan(into: session, settings: settings)
    }
  }

  public func cancelScan() {
    scanTask?.cancel()
  }

  /// Dismisses the current banner and re-enumerates on the next `scan(into:settings:)` call
  /// — DESIGN.md: "Retry (re-enumerate)."
  public func retry() {
    banner = nil
  }

  private func runScan(into session: DocumentSession, settings: AppSettings) async {
    // scanState is already .discovering -- set synchronously in scan() itself, see there.
    do {
      let device = try await resolveDevice()
      currentDeviceID = device.id
      try Task.checkCancellation()

      let scanSession = ScanSession(deviceID: device.id, mode: backendMode)
      let config = session.currentConfiguration(
        source: settings.source, extendLampTimeout: settings.extendLampTimeout)
      scanState = .scanning(progress: 0)
      // Fresh per scan -- see ProgressPublishPolicy's doc comment. A local var (not a
      // stored property) so there's no cross-scan state to reset between calls.
      var progressPolicy = ProgressPublishPolicy()

      for try await event in scanSession.scan(config: config) {
        switch event {
        case .started:
          break
        case .progress(let fraction):
          if progressPolicy.shouldPublish(fraction) {
            scanState = .scanning(progress: fraction)
          }
        case .completed(let page):
          // Crop happens here, before the page ever reaches `session.addPage` -- DESIGN.md
          // decision #9: "before it lands in the page strip / canvas preview," so the UI
          // only ever shows the auto-cropped result. `documentCropper` is a blocking Vision
          // call (same contract as `OCREngine.recognizeLines`), so it runs off the MainActor
          // via a detached Task, but is *awaited* here (not fire-and-forget like the OCR
          // background task below) since the crop must be done before this page is visible.
          let cropper = documentCropper
          let croppedPage = await Task.detached(priority: .userInitiated) {
            cropper(page)
          }.value
          let entry = session.addPage(croppedPage)
          if entry.ocrStatus == .pending {
            beginBackgroundOCR(
              pageID: entry.id, page: entry.page, session: session, settings: settings)
          }
        }
      }
      scanState = .idle
    } catch is CancellationError {
      scanState = .idle
    } catch let error as ScanError {
      scanState = .idle
      if case .cancelled = error {
        // Cancellation surfacing as ScanError.cancelled (rather than CancellationError,
        // depending on exactly where the race lands — see ScannerKit's own
        // CancellationTests) is expected, not a failure worth a banner.
      } else {
        banner = Self.banner(for: error)
      }
    } catch {
      scanState = .idle
      banner = Banner(message: "Unexpected error: \(error)", isRetryable: true)
    }
  }

  private func resolveDevice() async throws -> ScannerDevice {
    let devices = try await discovery.devices()
    guard let first = devices.first else {
      throw ScanError.deviceNotFound("no scanner devices found")
    }
    return first
  }

  /// Kicks off OCR for a just-scanned Text-mode page on a detached background task, so
  /// "Save PDF…" is instant by the time the user gets there (DESIGN.md's PDF flow). Runs
  /// against `PageNormalizer.normalize(page)` — the same image `PDFBuilder.append` would
  /// embed — so the precomputed lines line up with what Save will actually draw.
  private func beginBackgroundOCR(
    pageID: UUID, page: ScannedPage, session: DocumentSession, settings: AppSettings
  ) {
    let ocrRunner = self.ocrRunner
    let language = settings.ocrLanguage
    Task.detached(priority: .utility) {
      let normalized = PageNormalizer.normalize(page)
      do {
        let lines = try ocrRunner(normalized.image, language)
        await session.setOCRResult(lines, for: pageID)
      } catch {
        await session.setOCRFailed(for: pageID)
      }
    }
  }

  static func banner(for error: ScanError) -> Banner {
    switch error {
    case .deviceNotFound:
      return Banner(message: "Scanner not found — check the cable, then Retry.", isRetryable: true)
    case .deviceBusy:
      return Banner(
        message: "Scanner is busy (in use by another process) — Retry once it's free.",
        isRetryable: true)
    case .cancelled:
      return Banner(message: "Scan cancelled.", isRetryable: false)
    case .ioError(let message):
      return Banner(message: message, isRetryable: true)
    }
  }
}
