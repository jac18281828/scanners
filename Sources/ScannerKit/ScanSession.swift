import Foundation

/// SANE well-known option names (saneopts.h) `ScanSession`'s negotiation depends on.
private enum OptionName {
  static let mode = "mode"
  static let source = "source"
  static let resolution = "resolution"
  static let extendLampTimeout = "extend-lamp-timeout"
  static let topLeftX = "tl-x"
  static let topLeftY = "tl-y"
  static let bottomRightX = "br-x"
  static let bottomRightY = "br-y"
}

/// Drives one scan against one device: option negotiation, the SANE start/read loop, frame
/// decoding, and cancellation. Construct one per scan (or per multi-page session — nothing
/// here is single-use beyond the handle lifetime of a single `scan(config:)` call).
public struct ScanSession: Sendable {
  private let deviceID: String
  private let backend: any SaneBackend
  private let runner: SaneRunner

  public init(deviceID: String) {
    self.init(deviceID: deviceID, backend: RealSane.shared, runner: .shared)
  }

  init(deviceID: String, backend: any SaneBackend, runner: SaneRunner) {
    self.deviceID = deviceID
    self.backend = backend
    self.runner = runner
  }

  /// Read chunk size for `sane_read`. Kept modest (not a giant single buffer) so
  /// `.progress` events land at a reasonable cadence on a full-bed 600dpi+ scan.
  private static let readChunkSize: Int32 = 64 * 1024

  public func scan(config: ScanConfiguration) -> AsyncThrowingStream<ScanEvent, Error> {
    let deviceID = self.deviceID
    let backend = self.backend
    let runner = self.runner

    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          try await Self.runScan(
            deviceID: deviceID,
            backend: backend,
            runner: runner,
            config: config,
            continuation: continuation
          )
          continuation.finish()
        } catch {
          continuation.finish(throwing: ErrorMapper.map(error, deviceID: deviceID))
        }
      }
      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }

  // MARK: - Scan execution

  private static func runScan(
    deviceID: String,
    backend: any SaneBackend,
    runner: SaneRunner,
    config: ScanConfiguration,
    continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation
  ) async throws {
    let handle: SaneHandle
    do {
      handle = try await runner.run { try backend.open(deviceID) }
    } catch {
      throw ErrorMapper.mapOpenFailure(error, deviceID: deviceID)
    }

    do {
      let hardwareDPI = try await negotiateOptions(
        handle: handle, backend: backend, runner: runner, config: config)
      try Task.checkCancellation()
      let params = try await startAndValidateParams(
        handle: handle, backend: backend, runner: runner)

      let widthMM = Double(params.pixelsPerLine) / Double(hardwareDPI) * 25.4
      let heightMM = Double(params.lines) / Double(hardwareDPI) * 25.4

      continuation.yield(
        .started(
          ScanParametersInfo(
            mode: config.mode,
            requestedDPI: config.requestedDPI,
            hardwareDPI: hardwareDPI,
            widthPixels: Int(params.pixelsPerLine),
            heightPixels: Int(params.lines),
            widthMM: widthMM,
            heightMM: heightMM
          )
        )
      )

      let totalBytes = Int(params.bytesPerLine) * Int(params.lines)
      let pixelData = try await readFrameBytes(
        handle: handle, backend: backend, runner: runner, totalBytes: totalBytes,
        continuation: continuation)

      let image = try FrameDecoder.decode(bytes: pixelData, params: params)
      continuation.yield(
        .completed(
          ScannedPage(
            image: image,
            widthMM: widthMM,
            heightMM: heightMM,
            requestedDPI: config.requestedDPI,
            hardwareDPI: hardwareDPI,
            mode: config.mode
          )
        )
      )

      await runner.run { backend.cancel(handle) }
      await runner.run { backend.close(handle) }
    } catch {
      await runner.run { backend.cancel(handle) }
      await runner.run { backend.close(handle) }
      throw error
    }
  }

  /// Starts the scan and reads back the parameters that actually drive allocation and
  /// decoding. `sane_get_parameters` is only guaranteed accurate *after* `sane_start`:
  /// before start, `lines` may be -1 (unknown — legal for some sources) or an estimate, and
  /// the geometry can be revised at start. So start first, then trust only the post-start
  /// values (a pre-start `lines == -1` would trap the lineart intermediate buffer's
  /// `repeating:count:` allocation).
  private static func startAndValidateParams(
    handle: SaneHandle,
    backend: any SaneBackend,
    runner: SaneRunner
  ) async throws -> SaneParametersRecord {
    try await runner.run { try backend.start(handle) }
    let params = try await runner.run { try backend.parameters(handle) }

    guard params.lastFrame else {
      throw ScanError.ioError(
        "hp5590 emitted a multi-frame scan (last_frame=false after the first frame) — "
          + "unsupported."
      )
    }

    // Defence-in-depth against a non-conformant backend: negative dimensions would trap the
    // decode's buffer allocation and produce a bogus over-allocation for `reserveCapacity`.
    guard params.pixelsPerLine >= 0, params.lines >= 0, params.bytesPerLine >= 0 else {
      throw ScanError.ioError(
        "device reported invalid frame dimensions (pixelsPerLine=\(params.pixelsPerLine), "
          + "lines=\(params.lines), bytesPerLine=\(params.bytesPerLine))"
      )
    }

    return params
  }

  /// Reads the started scan to EOF on the shared runner, yielding `.progress` as bytes
  /// accumulate, and returns the full frame. `Task.checkCancellation` runs between chunks, so
  /// cancellation is honored at chunk boundaries (see `SaneRunner`'s serial-queue note for the
  /// blocked-read caveat).
  private static func readFrameBytes(
    handle: SaneHandle,
    backend: any SaneBackend,
    runner: SaneRunner,
    totalBytes: Int,
    continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation
  ) async throws -> [UInt8] {
    var pixelData = [UInt8]()
    pixelData.reserveCapacity(max(totalBytes, 0))
    while true {
      try Task.checkCancellation()
      let result = try await runner.run { try backend.read(handle, maxLength: readChunkSize) }
      pixelData.append(contentsOf: result.bytes)
      if totalBytes > 0 {
        continuation.yield(.progress(min(1.0, Double(pixelData.count) / Double(totalBytes))))
      }
      if result.reachedEOF {
        break
      }
    }
    return pixelData
  }

  // MARK: - Option negotiation

  /// Sets mode/source/resolution/area on the open handle and returns the dpi the hardware
  /// actually settled on. `ResolutionPolicy` picks the candidate native dpi up front; if
  /// the device itself reports SANE_INFO_INEXACT after setting it (meaning the requested
  /// value wasn't accepted verbatim), the actual applied value is read back and trusted
  /// over our own candidate — the hardware is the source of truth.
  private static func negotiateOptions(
    handle: SaneHandle,
    backend: any SaneBackend,
    runner: SaneRunner,
    config: ScanConfiguration
  ) async throws -> Int {
    var descriptors = try await runner.run { try backend.optionDescriptors(handle) }

    func index(named name: String) -> SaneOptionDescriptorRecord? {
      descriptors.first { $0.name == name }
    }

    // Applies a setOption call and, when the device reports SANE_INFO_RELOAD_OPTIONS,
    // re-fetches descriptors before any later lookup — hp5590 raises `br-y`'s max when
    // `source` becomes ADF, and that only shows up in a fresh descriptor fetch.
    func setOption(
      _ value: SaneOptionValue, at optionIndex: Int32
    ) async throws -> SaneSetOptionResult {
      let result = try await runner.run {
        try backend.setOption(handle, index: optionIndex, value: value)
      }
      if result.reloadOptions {
        descriptors = try await runner.run { try backend.optionDescriptors(handle) }
      }
      return result
    }

    // Mode is mandatory — every SANE backend has it, and without it we'd be scanning
    // whatever mode the device happened to power on in.
    guard let modeOption = index(named: OptionName.mode) else {
      throw ScanError.ioError("device has no '\(OptionName.mode)' option")
    }
    _ = try await setOption(.string(config.mode.saneModeName), at: modeOption.index)

    // Source is optional — not every device (or MockSane scenario) exposes it.
    if let sourceOption = index(named: OptionName.source) {
      _ = try await setOption(.string(config.source.saneSourceName), at: sourceOption.index)
    }

    // Lamp timeout is optional too — only the real hp5590 exposes `extend-lamp-timeout`
    // today (confirmed via `scanimage -A`); MockSane and any future backend without it are
    // left alone rather than erroring, same pattern as `source` above.
    if let lampOption = index(named: OptionName.extendLampTimeout) {
      _ = try await setOption(.bool(config.extendLampTimeout), at: lampOption.index)
    }

    guard let resolutionOption = index(named: OptionName.resolution) else {
      throw ScanError.ioError("device has no '\(OptionName.resolution)' option")
    }
    let candidateDPI = ResolutionPolicy.hardwareDPI(for: config.requestedDPI)
    let requestedValue: SaneOptionValue =
      resolutionOption.type == .fixed ? .fixed(Double(candidateDPI)) : .int(Int32(candidateDPI))
    let setResult = try await setOption(requestedValue, at: resolutionOption.index)

    var hardwareDPI = candidateDPI
    if setResult.inexact {
      let actual = try await runner.run {
        try backend.getOption(handle, index: resolutionOption.index)
      }
      switch actual {
      case .int(let intValue): hardwareDPI = Int(intValue)
      case .fixed(let fixedValue): hardwareDPI = Int(fixedValue.rounded())
      default: break
      }
    }

    try await negotiateArea(
      handle: handle, backend: backend, runner: runner, config: config, descriptors: descriptors)

    return hardwareDPI
  }

  private static func negotiateArea(
    handle: SaneHandle,
    backend: any SaneBackend,
    runner: SaneRunner,
    config: ScanConfiguration,
    descriptors: [SaneOptionDescriptorRecord]
  ) async throws {
    func option(named name: String) -> SaneOptionDescriptorRecord? {
      descriptors.first { $0.name == name }
    }

    guard let tlX = option(named: OptionName.topLeftX),
      let tlY = option(named: OptionName.topLeftY),
      let brX = option(named: OptionName.bottomRightX),
      let brY = option(named: OptionName.bottomRightY)
    else {
      // No geometry options at all — nothing to negotiate, device has one fixed area.
      return
    }

    func bounds(_ descriptor: SaneOptionDescriptorRecord) -> (min: Double, max: Double) {
      if case .range(let min, let max, _) = descriptor.constraint {
        return (min, max)
      }
      return (0, 0)
    }

    let x = bounds(tlX)
    let y = bounds(tlY)
    let xEnd = bounds(brX)
    let yEnd = bounds(brY)

    let area =
      config.area
      ?? ScanArea(
        topLeftXMM: x.min, topLeftYMM: y.min, widthMM: xEnd.max - x.min, heightMM: yEnd.max - y.min)

    func numericValue(_ mm: Double, type: SaneOptionType) -> SaneOptionValue {
      type == .fixed ? .fixed(mm) : .int(Int32(mm.rounded()))
    }

    let tlXValue = numericValue(area.topLeftXMM, type: tlX.type)
    let tlYValue = numericValue(area.topLeftYMM, type: tlY.type)
    let brXValue = numericValue(area.topLeftXMM + area.widthMM, type: brX.type)
    let brYValue = numericValue(area.topLeftYMM + area.heightMM, type: brY.type)

    _ = try await runner.run {
      try backend.setOption(handle, index: tlX.index, value: tlXValue)
    }
    _ = try await runner.run {
      try backend.setOption(handle, index: tlY.index, value: tlYValue)
    }
    _ = try await runner.run {
      try backend.setOption(handle, index: brX.index, value: brXValue)
    }
    _ = try await runner.run {
      try backend.setOption(handle, index: brY.index, value: brYValue)
    }
  }
}
