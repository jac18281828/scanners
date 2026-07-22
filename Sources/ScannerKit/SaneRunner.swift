import Foundation

/// Serializes every blocking call into a `SaneBackend` onto one dedicated background
/// queue, so ScannerKit never issues two SANE calls concurrently.
///
/// This matters for two independent reasons: `libsane`/`libusb` are not documented as
/// safely reentrant, and exactly one process may talk to the HP 4570c's USB endpoint at a
/// time (hardware discipline — see DESIGN.md). A serial `DispatchQueue` never runs two
/// enqueued blocks concurrently, which for a queue that only ever runs synchronous,
/// non-suspending work (as every `SaneBackend` method is) is equivalent in practice to a
/// single dedicated thread: exactly one SANE call in flight, always the same execution
/// context, never interleaved with another.
final class SaneRunner: Sendable {
  private let queue: DispatchQueue

  /// A process-wide default. `ScannerDiscovery` and `ScanSession` share this by default
  /// so that discovery and scanning — which may both run within one long-lived host
  /// process (the future GUI app) — are serialized against each other too, not just
  /// internally. Tests inject a fresh `SaneRunner` per case instead, to stay isolated.
  static let shared = SaneRunner()

  init(label: String = "dev.scanners.sane") {
    self.queue = DispatchQueue(label: label, qos: .userInitiated)
  }

  /// Runs `body` on the dedicated queue and bridges its (synchronous, blocking) result or
  /// error back into the calling async context.
  func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        do {
          continuation.resume(returning: try body())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Non-throwing variant, for cleanup calls (`sane_cancel`, `sane_close`) that never fail.
  func run(_ body: @escaping @Sendable () -> Void) async {
    await withCheckedContinuation { continuation in
      queue.async {
        body()
        continuation.resume()
      }
    }
  }
}
