import CSane
import Foundation

// MARK: - Scanning

extension RealSane {
  func parameters(_ handle: SaneHandle) throws -> SaneParametersRecord {
    let rawHandle = try resolvedHandle(handle)
    var rawParameters = SANE_Parameters()
    let status = withUnsafeMutablePointer(to: &rawParameters) { parametersPointer in
      sane_get_parameters(rawHandle, parametersPointer)
    }
    try check(status, context: "sane_get_parameters")
    return SaneParametersRecord(
      format: frameFormat(rawParameters.format),
      lastFrame: rawParameters.last_frame != 0,
      bytesPerLine: rawParameters.bytes_per_line,
      pixelsPerLine: rawParameters.pixels_per_line,
      lines: rawParameters.lines,
      depth: rawParameters.depth
    )
  }

  private func frameFormat(_ rawFormat: SANE_Frame) -> SaneFrameFormat {
    switch rawFormat {
    case SANE_FRAME_GRAY: return .gray
    case SANE_FRAME_RGB: return .rgb
    case SANE_FRAME_RED: return .red
    case SANE_FRAME_GREEN: return .green
    default: return .blue
    }
  }

  func start(_ handle: SaneHandle) throws {
    let rawHandle = try resolvedHandle(handle)
    let status = sane_start(rawHandle)
    try check(status, context: "sane_start")
  }

  func read(_ handle: SaneHandle, maxLength: Int32) throws -> SaneReadResult {
    let rawHandle = try resolvedHandle(handle)
    var buffer = [UInt8](repeating: 0, count: Int(maxLength))
    var length: SANE_Int = 0
    let status = buffer.withUnsafeMutableBufferPointer { bufferPointer in
      withUnsafeMutablePointer(to: &length) { lengthPointer in
        sane_read(rawHandle, bufferPointer.baseAddress, maxLength, lengthPointer)
      }
    }
    if status == SANE_STATUS_EOF {
      return SaneReadResult(bytes: [], reachedEOF: true)
    }
    try check(status, context: "sane_read")
    return SaneReadResult(bytes: Array(buffer.prefix(Int(length))), reachedEOF: false)
  }

  func cancel(_ handle: SaneHandle) {
    guard let rawHandle = handles[handle.raw] else { return }
    sane_cancel(rawHandle)
  }
}

// MARK: - Helpers

extension RealSane {
  func resolvedHandle(_ handle: SaneHandle) throws -> SANE_Handle {
    guard let rawHandle = handles[handle.raw] else {
      throw SaneCallFailure(
        status: .invalid, context: "resolvedHandle", message: "handle already closed")
    }
    return rawHandle
  }

  func string(_ cString: SANE_String_Const?) -> String? {
    guard let cString else { return nil }
    return String(cString: cString)
  }

  func check(_ status: SANE_Status, context: String) throws {
    guard status != SANE_STATUS_GOOD else { return }
    let message =
      sane_strstatus(status).map { String(cString: $0) } ?? "SANE status \(status.rawValue)"
    throw SaneCallFailure(status: rawStatus(status), context: context, message: message)
  }

  func rawStatus(_ status: SANE_Status) -> SaneRawStatus {
    Self.statusTable[status] ?? .ioError
  }

  static let statusTable: [SANE_Status: SaneRawStatus] = [
    SANE_STATUS_GOOD: .good,
    SANE_STATUS_UNSUPPORTED: .unsupported,
    SANE_STATUS_CANCELLED: .cancelled,
    SANE_STATUS_DEVICE_BUSY: .deviceBusy,
    SANE_STATUS_INVAL: .invalid,
    SANE_STATUS_EOF: .eof,
    SANE_STATUS_JAMMED: .jammed,
    SANE_STATUS_NO_DOCS: .noDocs,
    SANE_STATUS_COVER_OPEN: .coverOpen,
    SANE_STATUS_IO_ERROR: .ioError,
    SANE_STATUS_NO_MEM: .noMem,
    SANE_STATUS_ACCESS_DENIED: .accessDenied,
  ]
}
