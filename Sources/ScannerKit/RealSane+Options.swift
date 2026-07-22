import CSane
import Foundation

// MARK: - Options

extension RealSane {
  func optionDescriptors(_ handle: SaneHandle) throws -> [SaneOptionDescriptorRecord] {
    let rawHandle = try resolvedHandle(handle)
    let count = try optionCount(rawHandle)
    var results: [SaneOptionDescriptorRecord] = []
    var optionIndex: SANE_Int = 1
    while optionIndex < count {
      if let descriptorPointer = sane_get_option_descriptor(rawHandle, optionIndex) {
        results.append(convert(descriptorPointer.pointee, index: optionIndex))
      }
      optionIndex += 1
    }
    return results
  }

  private func optionCount(_ rawHandle: SANE_Handle) throws -> SANE_Int {
    var count: SANE_Int = 0
    let status = withUnsafeMutablePointer(to: &count) { countPointer in
      sane_control_option(rawHandle, 0, SANE_ACTION_GET_VALUE, countPointer, nil)
    }
    try check(status, context: "sane_control_option(0, GET_VALUE)")
    return count
  }

  private func convert(
    _ descriptor: SANE_Option_Descriptor,
    index: Int32
  ) -> SaneOptionDescriptorRecord {
    let type = optionType(descriptor.type)
    let constraint = convertConstraint(descriptor, type: type)
    return SaneOptionDescriptorRecord(
      index: index,
      name: string(descriptor.name) ?? "",
      title: string(descriptor.title) ?? "",
      type: type,
      unit: optionUnit(descriptor.unit),
      size: descriptor.size,
      isActive: (descriptor.cap & Int32(SANE_CAP_INACTIVE)) == 0,
      isSettable: (descriptor.cap & Int32(SANE_CAP_SOFT_SELECT)) != 0,
      constraint: constraint
    )
  }

  private func convertConstraint(
    _ descriptor: SANE_Option_Descriptor,
    type: SaneOptionType
  ) -> SaneOptionConstraint {
    let unfix: (SANE_Word) -> Double = { type == .fixed ? Double($0) / 65536.0 : Double($0) }
    switch descriptor.constraint_type {
    case SANE_CONSTRAINT_RANGE:
      guard let range = descriptor.constraint.range else { return .none }
      return .range(
        min: unfix(range.pointee.min),
        max: unfix(range.pointee.max),
        quant: unfix(range.pointee.quant)
      )
    case SANE_CONSTRAINT_WORD_LIST:
      return convertWordList(descriptor.constraint.word_list, unfix: unfix)
    case SANE_CONSTRAINT_STRING_LIST:
      return convertStringList(descriptor.constraint.string_list)
    default:
      return .none
    }
  }

  private func convertWordList(
    _ wordList: UnsafePointer<SANE_Word>?,
    unfix: (SANE_Word) -> Double
  ) -> SaneOptionConstraint {
    guard let wordList else { return .none }
    let count = Int(wordList[0])
    guard count > 0 else { return .wordList([]) }
    var values: [Double] = []
    for wordIndex in 1...count {
      values.append(unfix(wordList[wordIndex]))
    }
    return .wordList(values)
  }

  private func convertStringList(
    _ stringList: UnsafePointer<SANE_String_Const?>?
  ) -> SaneOptionConstraint {
    guard let stringList else { return .none }
    var values: [String] = []
    var stringIndex = 0
    while let entry = stringList[stringIndex] {
      values.append(String(cString: entry))
      stringIndex += 1
    }
    return .stringList(values)
  }

  private func optionType(_ rawType: SANE_Value_Type) -> SaneOptionType {
    switch rawType {
    case SANE_TYPE_BOOL: return .bool
    case SANE_TYPE_INT: return .int
    case SANE_TYPE_FIXED: return .fixed
    case SANE_TYPE_STRING: return .string
    case SANE_TYPE_BUTTON: return .button
    default: return .group
    }
  }

  private func optionUnit(_ rawUnit: SANE_Unit) -> SaneOptionUnit {
    switch rawUnit {
    case SANE_UNIT_PIXEL: return .pixel
    case SANE_UNIT_BIT: return .bit
    case SANE_UNIT_MM: return .millimeter
    case SANE_UNIT_DPI: return .dpi
    case SANE_UNIT_PERCENT: return .percent
    case SANE_UNIT_MICROSECOND: return .microsecond
    default: return .none
    }
  }

  func getOption(_ handle: SaneHandle, index: Int32) throws -> SaneOptionValue {
    let rawHandle = try resolvedHandle(handle)
    guard let descriptorPointer = sane_get_option_descriptor(rawHandle, index) else {
      throw SaneCallFailure(
        status: .invalid, context: "getOption(\(index))", message: "no such option")
    }
    switch optionType(descriptorPointer.pointee.type) {
    case .bool:
      let scalar: SANE_Bool = try getScalar(rawHandle, index)
      return .bool(scalar != 0)
    case .int:
      let scalar: SANE_Int = try getScalar(rawHandle, index)
      return .int(scalar)
    case .fixed:
      let scalar: SANE_Word = try getScalar(rawHandle, index)
      return .fixed(Double(scalar) / 65536.0)
    case .string:
      return try getStringOption(rawHandle, index: index, size: Int(descriptorPointer.pointee.size))
    case .button, .group:
      throw SaneCallFailure(
        status: .unsupported, context: "getOption(\(index))", message: "not a readable option")
    }
  }

  private func getStringOption(
    _ rawHandle: SANE_Handle,
    index: Int32,
    size: Int
  ) throws -> SaneOptionValue {
    var buffer = [CChar](repeating: 0, count: max(size, 1))
    let status = buffer.withUnsafeMutableBufferPointer { bufferPointer in
      sane_control_option(rawHandle, index, SANE_ACTION_GET_VALUE, bufferPointer.baseAddress, nil)
    }
    try check(status, context: "sane_control_option(\(index), GET_VALUE, string)")
    return .string(buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) })
  }

  func setOption(
    _ handle: SaneHandle,
    index: Int32,
    value: SaneOptionValue
  ) throws -> SaneSetOptionResult {
    let rawHandle = try resolvedHandle(handle)
    let info = try setInfo(rawHandle, index: index, value: value)
    return SaneSetOptionResult(
      inexact: (info & SANE_INFO_INEXACT) != 0,
      reloadOptions: (info & SANE_INFO_RELOAD_OPTIONS) != 0,
      reloadParams: (info & SANE_INFO_RELOAD_PARAMS) != 0
    )
  }

  private func setInfo(
    _ rawHandle: SANE_Handle,
    index: Int32,
    value: SaneOptionValue
  ) throws -> SANE_Int {
    switch value {
    case .bool(let flag):
      return try setScalar(rawHandle, index, SANE_Bool(flag ? SANE_TRUE : SANE_FALSE))
    case .int(let intValue):
      return try setScalar(rawHandle, index, SANE_Int(intValue))
    case .fixed(let fixedValue):
      return try setScalar(rawHandle, index, SANE_Word((fixedValue * 65536.0).rounded()))
    case .string(let text):
      return try setStringOption(rawHandle, index: index, text: text)
    }
  }

  private func setStringOption(
    _ rawHandle: SANE_Handle,
    index: Int32,
    text: String
  ) throws -> SANE_Int {
    var info: SANE_Int = 0
    var bytes = Array(text.utf8CString)
    let status = bytes.withUnsafeMutableBufferPointer { bufferPointer in
      withUnsafeMutablePointer(to: &info) { infoPointer in
        sane_control_option(
          rawHandle, index, SANE_ACTION_SET_VALUE, bufferPointer.baseAddress, infoPointer)
      }
    }
    try check(status, context: "sane_control_option(\(index), SET_VALUE, string)")
    return info
  }

  // SANE_Bool, SANE_Int, and SANE_Word are all typealiases for the same underlying Int32,
  // so `T: ExpressibleByIntegerLiteral` is enough to zero-initialize any of them safely —
  // no unsafeBitCast trickery needed.
  private func getScalar<T: ExpressibleByIntegerLiteral>(
    _ rawHandle: SANE_Handle,
    _ index: Int32
  ) throws -> T {
    var scalar: T = 0
    let status = withUnsafeMutablePointer(to: &scalar) { scalarPointer in
      sane_control_option(rawHandle, index, SANE_ACTION_GET_VALUE, scalarPointer, nil)
    }
    try check(status, context: "sane_control_option(\(index), GET_VALUE)")
    return scalar
  }

  private func setScalar<T>(
    _ rawHandle: SANE_Handle,
    _ index: Int32,
    _ value: T
  ) throws -> SANE_Int {
    var scalar = value
    var info: SANE_Int = 0
    let status = withUnsafeMutablePointer(to: &scalar) { scalarPointer in
      withUnsafeMutablePointer(to: &info) { infoPointer in
        sane_control_option(rawHandle, index, SANE_ACTION_SET_VALUE, scalarPointer, infoPointer)
      }
    }
    try check(status, context: "sane_control_option(\(index), SET_VALUE)")
    return info
  }
}
