/// Selects which `SaneBackend` a `ScannerDiscovery`/`ScanSession` talks to.
///
/// `SaneBackend`/`RealSane`/`MockSane` all stay internal to ScannerKit — this enum is the
/// *only* public seam into mock mode, so a consumer (Phase 5's `ScannersApp`) can drive the
/// exact same option-negotiation/scan/cancel code paths `MockSane` exercises in
/// `ScannerKitTests` without ever touching hardware, and without ScannerKit having to widen
/// its internal test-double surface to `public`. `.mock` never opens libusb or the vendored
/// `libsane.dylib` at all.
public enum ScannerBackendMode: Sendable, Equatable {
  case real
  case mock
}

extension ScannerDiscovery {
  /// `.real` behaves identically to the no-argument `init()`. `.mock` talks to a fresh,
  /// default-configured `MockSane` — the same "hp5590:libusb:000:017 / ScanJet 4570c"
  /// device `MockSane.Configuration.default` reports in `ScannerKitTests`.
  public init(mode: ScannerBackendMode) {
    switch mode {
    case .real: self.init(backend: RealSane.shared, runner: .shared)
    case .mock: self.init(backend: MockSane(), runner: SaneRunner())
    }
  }
}

extension ScanSession {
  /// `.real` behaves identically to `init(deviceID:)`. `.mock` drives a fresh, default-
  /// configured `MockSane` — see `ScannerDiscovery.init(mode:)`. Each call constructs its
  /// own `MockSane` instance (matching this type's own "construct one per scan" contract,
  /// documented on the type itself); since `MockSane.Configuration.default` is
  /// deterministic, this is behaviorally indistinguishable from sharing one instance for
  /// every caller that only ever scans the default device.
  public init(deviceID: String, mode: ScannerBackendMode) {
    switch mode {
    case .real: self.init(deviceID: deviceID, backend: RealSane.shared, runner: .shared)
    case .mock: self.init(deviceID: deviceID, backend: MockSane(), runner: SaneRunner())
    }
  }
}
