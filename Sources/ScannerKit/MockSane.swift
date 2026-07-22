import Foundation

/// Pure-Swift `SaneBackend` for tests: a scripted device list, option negotiation
/// (including SANE_INFO_INEXACT dpi-snapping semantics), and synthetic frame data for all
/// three scan modes. Never touches CSane/libsane — safe to run with no hardware and no
/// vendored dylibs present.
///
/// Modeled after the real hp5590's option layout as described in DESIGN.md: `mode`
/// (string: Gray/Color/Lineart), `source` (string: Flatbed/ADF), `resolution` (int,
/// word-list constrained), and `tl-x`/`tl-y`/`br-x`/`br-y` (fixed, range-constrained, mm).
final class MockSane: SaneBackend, @unchecked Sendable {
  struct Configuration: Sendable {
    var devices: [SaneDeviceRecord]
    /// The dpi values the simulated hardware itself accepts exactly. Defaults to
    /// `ResolutionPolicy.nativeDPI` (the "well-behaved hardware" case); tests that want to
    /// exercise SANE_INFO_INEXACT snapping pass a narrower list so a `ResolutionPolicy`
    /// candidate the mock doesn't recognize gets snapped and reported back as inexact.
    var supportedDPI: [Int32]
    var bedWidthMM: Double
    var bedHeightMM: Double
    /// If set, `open` fails with this status instead of succeeding.
    var openFailure: SaneRawStatus?
    /// Per-`sane_read` artificial delay, for cancellation tests that need a wide-enough
    /// window to reliably cancel mid-scan. Zero for every other test, so the suite stays
    /// fast.
    var readDelay: TimeInterval

    static let `default` = Configuration(
      devices: [
        SaneDeviceRecord(
          name: "hp5590:libusb:000:017",
          vendor: "Hewlett-Packard",
          model: "ScanJet 4570c",
          type: "flatbed scanner"
        )
      ],
      supportedDPI: ResolutionPolicy.nativeDPI.map(Int32.init),
      bedWidthMM: 215.899,
      bedHeightMM: 297.699,
      openFailure: nil,
      readDelay: 0
    )
  }

  enum OptionIndex: Int32 {
    case mode = 1
    case source = 2
    case resolution = 3
    case topLeftX = 4
    case topLeftY = 5
    case bottomRightX = 6
    case bottomRightY = 7
  }

  // Not `private`: shared with the MockSane+Options.swift / MockSane+Scanning.swift
  // extensions in other files. Still module-internal — MockSane itself is never public.
  let configuration: Configuration
  let lock = NSLock()
  var nextHandleID = 0
  var openHandles: Set<Int> = []
  var optionValues: [Int32: SaneOptionValue] = [:]
  var readCursor: [Int: Int] = [:]
  var frameCache: [Int: [UInt8]] = [:]
  var devicesOverride: [SaneDeviceRecord]?

  var cancelCallCount = 0

  init(configuration: Configuration = .default) {
    self.configuration = configuration
    self.optionValues = [
      OptionIndex.mode.rawValue: .string("Gray"),
      OptionIndex.source.rawValue: .string("Flatbed"),
      OptionIndex.resolution.rawValue: .int(Int32(ResolutionPolicy.nativeDPI[0])),
      OptionIndex.topLeftX.rawValue: .fixed(0),
      OptionIndex.topLeftY.rawValue: .fixed(0),
      OptionIndex.bottomRightX.rawValue: .fixed(configuration.bedWidthMM),
      OptionIndex.bottomRightY.rawValue: .fixed(configuration.bedHeightMM),
    ]
  }

  /// Test-only hook simulating a replug: subsequent `listDevices()` calls return this list
  /// instead of `configuration.devices`, without needing a new `MockSane` instance.
  func setDevicesForTesting(_ devices: [SaneDeviceRecord]) {
    lock.lock()
    defer { lock.unlock() }
    devicesOverride = devices
  }
}

// MARK: - Devices, open/close

extension MockSane {
  func listDevices() throws -> [SaneDeviceRecord] {
    lock.lock()
    defer { lock.unlock() }
    return devicesOverride ?? configuration.devices
  }

  func open(_ deviceName: String) throws -> SaneHandle {
    if let failure = configuration.openFailure {
      throw SaneCallFailure(
        status: failure, context: "sane_open(\(deviceName))", message: "mocked failure")
    }
    let known = try listDevices()
    guard known.contains(where: { $0.name == deviceName }) else {
      throw SaneCallFailure(
        status: .invalid, context: "sane_open(\(deviceName))", message: "no such device")
    }
    lock.lock()
    defer { lock.unlock() }
    let newID = nextHandleID
    nextHandleID += 1
    openHandles.insert(newID)
    return SaneHandle(raw: newID)
  }

  func close(_ handle: SaneHandle) {
    lock.lock()
    defer { lock.unlock() }
    openHandles.remove(handle.raw)
    readCursor.removeValue(forKey: handle.raw)
    frameCache.removeValue(forKey: handle.raw)
  }
}
