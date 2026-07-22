/// ScannerKit's public error taxonomy. Deliberately never carries a raw SANE_Status —
/// `ErrorMapper` translates whatever the backend threw into one of these, with a readable
/// message baked in for the catch-all `ioError` case.
public enum ScanError: Error, Sendable, Equatable {
  /// `sane_open` (or discovery) found no such device — most often a stale device id from
  /// before a replug (device strings like `hp5590:libusb:000:016` change across replugs;
  /// always re-enumerate rather than caching one).
  case deviceNotFound(String)

  /// The device exists but is already in use by another process — SANE_STATUS_DEVICE_BUSY.
  /// Hardware discipline: at most one process may talk to the scanner at a time.
  case deviceBusy(String)

  /// The scan was cancelled, either by explicit Swift task cancellation or because the
  /// device itself reported SANE_STATUS_CANCELLED.
  case cancelled

  /// Any other SANE failure (I/O error, jam, cover open, out of memory, unsupported
  /// operation, ...), rendered as a human-readable message via `sane_strstatus`.
  case ioError(String)
}

extension ScanError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .deviceNotFound(let id): return "scanner not found: \(id)"
    case .deviceBusy(let id): return "scanner busy: \(id)"
    case .cancelled: return "scan cancelled"
    case .ioError(let message): return message
    }
  }
}

/// Translates whatever a `SaneBackend` threw (or a Swift cancellation) into the public
/// `ScanError` taxonomy. Internal — `ScanError` itself is the public surface.
enum ErrorMapper {
  static func map(_ error: Error, deviceID: String) -> ScanError {
    if let scanError = error as? ScanError {
      return scanError
    }
    if error is CancellationError {
      return .cancelled
    }
    if let failure = error as? SaneCallFailure {
      switch failure.status {
      case .invalid:
        return .deviceNotFound(deviceID)
      case .deviceBusy:
        return .deviceBusy(deviceID)
      case .cancelled:
        return .cancelled
      default:
        return .ioError("\(failure.context): \(failure.message)")
      }
    }
    return .ioError(String(describing: error))
  }
}
