import Foundation

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

  /// SANE well-known option names (saneopts.h) this negotiation depends on.
  private enum OptionName {
    static let mode = "mode"
    static let source = "source"
    static let resolution = "resolution"
    static let topLeftX = "tl-x"
    static let topLeftY = "tl-y"
    static let bottomRightX = "br-x"
    static let bottomRightY = "br-y"
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
    let handle = try await runner.run { try backend.open(deviceID) }

    do {
      let hardwareDPI = try await negotiateOptions(
        handle: handle, backend: backend, runner: runner, config: config)
      let params = try await runner.run { try backend.parameters(handle) }

      guard params.lastFrame else {
        throw ScanError.ioError(
          "hp5590 emitted a multi-frame scan (last_frame=false after the first frame) — "
            + "unsupported; escalate per Phase 3 spec rather than guessing a decoder."
        )
      }

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

      try await runner.run { try backend.start(handle) }

      let totalBytes = Int(params.bytesPerLine) * Int(params.lines)
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

      await runner.run { backend.close(handle) }
    } catch {
      await runner.run { backend.cancel(handle) }
      await runner.run { backend.close(handle) }
      throw error
    }
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
    let descriptors = try await runner.run { try backend.optionDescriptors(handle) }

    func index(named name: String) -> SaneOptionDescriptorRecord? {
      descriptors.first { $0.name == name }
    }

    // Mode is mandatory — every SANE backend has it, and without it we'd be scanning
    // whatever mode the device happened to power on in.
    guard let modeOption = index(named: OptionName.mode) else {
      throw ScanError.ioError("device has no '\(OptionName.mode)' option")
    }
    _ = try await runner.run {
      try backend.setOption(
        handle, index: modeOption.index, value: .string(config.mode.saneModeName))
    }

    // Source is optional — not every device (or MockSane scenario) exposes it.
    if let sourceOption = index(named: OptionName.source) {
      _ = try await runner.run {
        try backend.setOption(
          handle, index: sourceOption.index, value: .string(config.source.saneSourceName))
      }
    }

    guard let resolutionOption = index(named: OptionName.resolution) else {
      throw ScanError.ioError("device has no '\(OptionName.resolution)' option")
    }
    let candidateDPI = ResolutionPolicy.hardwareDPI(for: config.requestedDPI)
    let requestedValue: SaneOptionValue =
      resolutionOption.type == .fixed ? .fixed(Double(candidateDPI)) : .int(Int32(candidateDPI))
    let setResult = try await runner.run {
      try backend.setOption(handle, index: resolutionOption.index, value: requestedValue)
    }

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
