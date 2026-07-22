import Foundation

// MARK: - Option descriptors

extension MockSane {
  func optionDescriptors(_ handle: SaneHandle) throws -> [SaneOptionDescriptorRecord] {
    let bedW = configuration.bedWidthMM
    let bedH = configuration.bedHeightMM
    var descriptors = [
      stringOption(.mode, name: "mode", title: "Scan mode", values: ["Gray", "Color", "Lineart"]),
      stringOption(.source, name: "source", title: "Scan source", values: ["Flatbed", "ADF"]),
      resolutionOption(),
      rangeOption(.topLeftX, name: "tl-x", title: "Top-left x", max: bedW),
      rangeOption(.topLeftY, name: "tl-y", title: "Top-left y", max: bedH),
      rangeOption(.bottomRightX, name: "br-x", title: "Bottom-right x", max: bedW),
      rangeOption(.bottomRightY, name: "br-y", title: "Bottom-right y", max: bedH),
    ]
    if configuration.includesLampTimeoutOption {
      descriptors.append(
        boolOption(.lampTimeout, name: "extend-lamp-timeout", title: "Extend lamp timeout"))
    }
    return descriptors
  }

  private func boolOption(
    _ index: OptionIndex,
    name: String,
    title: String
  ) -> SaneOptionDescriptorRecord {
    SaneOptionDescriptorRecord(
      index: index.rawValue,
      name: name,
      title: title,
      type: .bool,
      unit: .none,
      size: 4,
      isActive: true,
      isSettable: true,
      constraint: .none
    )
  }

  private func resolutionOption() -> SaneOptionDescriptorRecord {
    SaneOptionDescriptorRecord(
      index: OptionIndex.resolution.rawValue,
      name: "resolution",
      title: "Scan resolution",
      type: .int,
      unit: .dpi,
      size: 4,
      isActive: true,
      isSettable: true,
      constraint: .wordList(configuration.supportedDPI.map(Double.init))
    )
  }

  private func stringOption(
    _ index: OptionIndex,
    name: String,
    title: String,
    values: [String]
  ) -> SaneOptionDescriptorRecord {
    SaneOptionDescriptorRecord(
      index: index.rawValue,
      name: name,
      title: title,
      type: .string,
      unit: .none,
      size: 16,
      isActive: true,
      isSettable: true,
      constraint: .stringList(values)
    )
  }

  private func rangeOption(
    _ index: OptionIndex,
    name: String,
    title: String,
    max: Double
  ) -> SaneOptionDescriptorRecord {
    SaneOptionDescriptorRecord(
      index: index.rawValue,
      name: name,
      title: title,
      type: .fixed,
      unit: .millimeter,
      size: 4,
      isActive: true,
      isSettable: true,
      constraint: .range(min: 0, max: max, quant: 0)
    )
  }
}

// MARK: - Option get/set

extension MockSane {
  func getOption(_ handle: SaneHandle, index: Int32) throws -> SaneOptionValue {
    lock.lock()
    defer { lock.unlock() }
    guard let value = optionValues[index] else {
      throw SaneCallFailure(
        status: .invalid, context: "getOption(\(index))", message: "no such option")
    }
    return value
  }

  func setOption(
    _ handle: SaneHandle,
    index: Int32,
    value: SaneOptionValue
  ) throws -> SaneSetOptionResult {
    lock.lock()
    defer { lock.unlock() }

    guard let option = OptionIndex(rawValue: index) else {
      throw SaneCallFailure(
        status: .invalid, context: "setOption(\(index))", message: "no such option")
    }

    switch option {
    case .resolution:
      return try setResolution(index: index, value: value)
    case .mode, .source:
      return try setStringOption(index: index, value: value)
    case .topLeftX, .topLeftY, .bottomRightX, .bottomRightY:
      return try setFixedOption(index: index, value: value)
    case .lampTimeout:
      return try setBoolOption(index: index, value: value)
    }
  }

  private func setBoolOption(index: Int32, value: SaneOptionValue) throws -> SaneSetOptionResult {
    guard case .bool = value else {
      throw SaneCallFailure(
        status: .invalid, context: "setOption(\(index))", message: "expected bool")
    }
    optionValues[index] = value
    return .exact
  }

  /// Snaps a requested dpi to the nearest value the simulated hardware actually supports
  /// and reports SANE_INFO_INEXACT when it had to — the behavior
  /// `ScanSession.negotiateOptions` reads back from when it sees `inexact == true`.
  private func setResolution(index: Int32, value: SaneOptionValue) throws -> SaneSetOptionResult {
    guard case .int(let requested) = value else {
      throw SaneCallFailure(
        status: .invalid, context: "setOption(resolution)", message: "expected int")
    }
    if configuration.supportedDPI.contains(requested) {
      optionValues[index] = .int(requested)
      return .exact
    }
    let snapped =
      configuration.supportedDPI.min(by: { abs($0 - requested) < abs($1 - requested) }) ?? requested
    optionValues[index] = .int(snapped)
    return SaneSetOptionResult(inexact: true, reloadOptions: false, reloadParams: true)
  }

  private func setStringOption(index: Int32, value: SaneOptionValue) throws -> SaneSetOptionResult {
    guard case .string = value else {
      throw SaneCallFailure(
        status: .invalid, context: "setOption(\(index))", message: "expected string")
    }
    optionValues[index] = value
    return .exact
  }

  private func setFixedOption(index: Int32, value: SaneOptionValue) throws -> SaneSetOptionResult {
    guard case .fixed(let mm) = value else {
      throw SaneCallFailure(
        status: .invalid, context: "setOption(\(index))", message: "expected fixed")
    }
    optionValues[index] = .fixed(mm)
    return .exact
  }
}
