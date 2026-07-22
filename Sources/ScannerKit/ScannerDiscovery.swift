/// A discovered scanner. `id` is the raw SANE device string (e.g.
/// `hp5590:libusb:000:016`) — DESIGN.md notes bus/address vary per plug event, so callers
/// must re-enumerate on demand rather than caching one across a replug.
public struct ScannerDevice: Sendable, Identifiable, Equatable {
  public let id: String
  public let vendor: String
  public let model: String
  public let type: String

  public var displayName: String {
    "\(vendor) \(model)"
  }
}

/// Enumerates available scanners. Stateless and cheap to construct — call `devices()`
/// fresh whenever you need current results rather than holding onto a stale list.
public struct ScannerDiscovery: Sendable {
  private let backend: any SaneBackend
  private let runner: SaneRunner

  public init() {
    self.init(backend: RealSane.shared, runner: .shared)
  }

  init(backend: any SaneBackend, runner: SaneRunner) {
    self.backend = backend
    self.runner = runner
  }

  public func devices() async throws -> [ScannerDevice] {
    let backend = self.backend
    do {
      let records = try await runner.run { try backend.listDevices() }
      return records.map {
        ScannerDevice(id: $0.name, vendor: $0.vendor, model: $0.model, type: $0.type)
      }
    } catch {
      throw ErrorMapper.map(error, deviceID: "")
    }
  }
}
