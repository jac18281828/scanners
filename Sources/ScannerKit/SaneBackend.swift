/// Everything ScannerKit needs from a SANE-shaped backend, in the Swift-native terms
/// defined by SaneModel.swift. `RealSane` implements this against the vendored C library;
/// `MockSane` implements it in pure Swift for the test suite. All methods are synchronous
/// and blocking by design — callers route them through `SaneRunner` to get async behavior
/// without ever issuing two SANE calls concurrently.
protocol SaneBackend: Sendable {
  func listDevices() throws -> [SaneDeviceRecord]

  func open(_ deviceName: String) throws -> SaneHandle
  func close(_ handle: SaneHandle)

  /// All non-synthetic option descriptors (index 1 and up — index 0 is always the
  /// "number of options" bookkeeping slot the SANE standard mandates and callers never
  /// need directly).
  func optionDescriptors(_ handle: SaneHandle) throws -> [SaneOptionDescriptorRecord]

  func getOption(_ handle: SaneHandle, index: Int32) throws -> SaneOptionValue
  func setOption(_ handle: SaneHandle, index: Int32, value: SaneOptionValue) throws
    -> SaneSetOptionResult

  func parameters(_ handle: SaneHandle) throws -> SaneParametersRecord

  func start(_ handle: SaneHandle) throws
  func read(_ handle: SaneHandle, maxLength: Int32) throws -> SaneReadResult
  func cancel(_ handle: SaneHandle)
}
