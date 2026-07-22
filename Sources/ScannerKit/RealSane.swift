import CSane
import Foundation

/// `SaneBackend` implementation backed by the real vendored `libsane`/`libusb` via the
/// `CSane` C shim. All methods are blocking C calls — callers must route them through
/// `SaneRunner`; this type does no threading of its own and is not safe to call from
/// multiple threads concurrently (mirrors the C library it wraps).
///
/// `sane_init` is deferred until the first call (rather than done in `init()`) so that
/// constructing a `RealSane` — including the process-wide `RealSane.shared` — can never
/// fail or block. `sane_exit` is deliberately never called: this type's only instance is
/// process-lifetime (`RealSane.shared`), and letting process exit reclaim the library
/// avoids the failure mode where a still-in-flight scan handle outlives an explicit
/// `sane_exit()` call.
final class RealSane: SaneBackend, @unchecked Sendable {
  static let shared = RealSane()

  private var initialized = false
  // Not `private`: shared with the RealSane+Options.swift / RealSane+Scanning.swift
  // extensions in other files. Still module-internal — RealSane itself is never public.
  var handles: [Int: SANE_Handle] = [:]
  private var nextHandleID = 0

  private func ensureInitialized() throws {
    guard !initialized else { return }
    var versionCode: SANE_Int = 0
    let status = sane_init(&versionCode, nil)
    try check(status, context: "sane_init")
    initialized = true
  }
}

// MARK: - Devices, open/close

extension RealSane {
  func listDevices() throws -> [SaneDeviceRecord] {
    try ensureInitialized()
    var listPointer: UnsafeMutablePointer<UnsafePointer<SANE_Device>?>?
    let status = sane_get_devices(&listPointer, SANE_FALSE)
    try check(status, context: "sane_get_devices")

    var results: [SaneDeviceRecord] = []
    if let listPointer {
      var deviceIndex = 0
      while let device = listPointer[deviceIndex] {
        let record = device.pointee
        results.append(
          SaneDeviceRecord(
            name: string(record.name) ?? "",
            vendor: string(record.vendor) ?? "",
            model: string(record.model) ?? "",
            type: string(record.type) ?? ""
          )
        )
        deviceIndex += 1
      }
    }
    return results
  }

  func open(_ deviceName: String) throws -> SaneHandle {
    try ensureInitialized()
    var rawHandle: SANE_Handle?
    let status = deviceName.withCString { cname in
      sane_open(cname, &rawHandle)
    }
    try check(status, context: "sane_open(\(deviceName))")
    guard let rawHandle else {
      throw SaneCallFailure(
        status: .ioError, context: "sane_open(\(deviceName))", message: "no handle returned")
    }
    let newID = nextHandleID
    nextHandleID += 1
    handles[newID] = rawHandle
    return SaneHandle(raw: newID)
  }

  func close(_ handle: SaneHandle) {
    guard let rawHandle = handles.removeValue(forKey: handle.raw) else { return }
    sane_close(rawHandle)
  }
}
