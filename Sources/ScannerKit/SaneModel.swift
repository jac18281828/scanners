/// Swift-native mirrors of the SANE C types (SANE_Status, SANE_Value_Type, SANE_Frame,
/// SANE_Parameters, option descriptors/values/constraints).
///
/// Everything in this file is intentionally free of any dependency on `CSane` — `RealSane`
/// is the only place that converts between these and the raw SANE_* types, so `MockSane`
/// (used throughout the test suite) never needs to link or import the C shim. This is also
/// what keeps the "no public ScannerKit API takes or returns raw SANE types" gate trivially
/// true: even this internal layer never mentions a SANE_* type.

/// Opaque handle to an open device, scoped to whichever `SaneBackend` issued it. Backed by
/// a small integer index rather than a raw pointer so `MockSane` can implement it without
/// any unsafe memory of its own.
struct SaneHandle: Hashable, Sendable {
  let raw: Int
}

struct SaneDeviceRecord: Sendable, Equatable {
  let name: String
  let vendor: String
  let model: String
  let type: String
}

enum SaneOptionType: Sendable, Equatable {
  case bool
  case int
  case fixed
  case string
  case button
  case group
}

enum SaneOptionUnit: Sendable, Equatable {
  case none
  case pixel
  case bit
  case millimeter
  case dpi
  case percent
  case microsecond
}

enum SaneOptionConstraint: Sendable, Equatable {
  case none
  case range(min: Double, max: Double, quant: Double)
  case wordList([Double])
  case stringList([String])
}

struct SaneOptionDescriptorRecord: Sendable, Equatable {
  let index: Int32
  let name: String
  let title: String
  let type: SaneOptionType
  let unit: SaneOptionUnit
  let size: Int32
  let isActive: Bool
  let isSettable: Bool
  let constraint: SaneOptionConstraint
}

enum SaneOptionValue: Sendable, Equatable {
  case bool(Bool)
  case int(Int32)
  case fixed(Double)
  case string(String)
}

/// Mirrors the three SANE_INFO_* bits `sane_control_option` may set after `SET_VALUE`.
struct SaneSetOptionResult: Sendable, Equatable {
  let inexact: Bool
  let reloadOptions: Bool
  let reloadParams: Bool

  static let exact = SaneSetOptionResult(inexact: false, reloadOptions: false, reloadParams: false)
}

enum SaneFrameFormat: Sendable, Equatable {
  case gray
  case rgb
  case red
  case green
  case blue
}

struct SaneParametersRecord: Sendable, Equatable {
  let format: SaneFrameFormat
  let lastFrame: Bool
  let bytesPerLine: Int32
  let pixelsPerLine: Int32
  let lines: Int32
  let depth: Int32
}

struct SaneReadResult: Sendable {
  let bytes: [UInt8]
  let reachedEOF: Bool
}

/// Swift mirror of SANE_Status, used only internally between a `SaneBackend` and the
/// error-mapping layer that turns it into the public `ScanError` taxonomy.
enum SaneRawStatus: Sendable, Equatable {
  case good
  case unsupported
  case cancelled
  case deviceBusy
  case invalid
  case eof
  case jammed
  case noDocs
  case coverOpen
  case ioError
  case noMem
  case accessDenied
}

/// Thrown by `SaneBackend` implementations when a call fails. Internal only — never crosses
/// the public ScannerKit API surface; `ErrorMapper` translates it into `ScanError`.
struct SaneCallFailure: Error, Sendable {
  let status: SaneRawStatus
  let context: String
  let message: String
}
