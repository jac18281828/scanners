import Foundation

// MARK: - Scanning

extension MockSane {
  func parameters(_ handle: SaneHandle) throws -> SaneParametersRecord {
    lock.lock()
    let (width, height) = currentDimensionsLocked()
    let mode = currentModeLocked()
    lock.unlock()
    return Self.parametersRecord(mode: mode, width: width, height: height)
  }

  private static func parametersRecord(
    mode: String,
    width: Int,
    height: Int
  ) -> SaneParametersRecord {
    switch mode {
    case "Color":
      return SaneParametersRecord(
        format: .rgb,
        lastFrame: true,
        bytesPerLine: Int32(width * 3),
        pixelsPerLine: Int32(width),
        lines: Int32(height),
        depth: 8
      )
    case "Lineart":
      let bytesPerLine = Int32((width + 7) / 8)
      return SaneParametersRecord(
        format: .gray,
        lastFrame: true,
        bytesPerLine: bytesPerLine,
        pixelsPerLine: Int32(width),
        lines: Int32(height),
        depth: 1
      )
    default:
      return SaneParametersRecord(
        format: .gray,
        lastFrame: true,
        bytesPerLine: Int32(width),
        pixelsPerLine: Int32(width),
        lines: Int32(height),
        depth: 8
      )
    }
  }

  func start(_ handle: SaneHandle) throws {
    let params = try parameters(handle)
    lock.lock()
    defer { lock.unlock() }
    frameCache[handle.raw] = Self.syntheticFrame(params: params)
    readCursor[handle.raw] = 0
  }

  func read(_ handle: SaneHandle, maxLength: Int32) throws -> SaneReadResult {
    if configuration.readDelay > 0 {
      Thread.sleep(forTimeInterval: configuration.readDelay)
    }
    lock.lock()
    defer { lock.unlock() }
    guard let frame = frameCache[handle.raw], let cursor = readCursor[handle.raw] else {
      throw SaneCallFailure(status: .invalid, context: "read", message: "sane_start not called")
    }
    if cursor >= frame.count {
      return SaneReadResult(bytes: [], reachedEOF: true)
    }
    let end = min(cursor + Int(maxLength), frame.count)
    let chunk = Array(frame[cursor..<end])
    readCursor[handle.raw] = end
    return SaneReadResult(bytes: chunk, reachedEOF: false)
  }

  func cancel(_ handle: SaneHandle) {
    lock.lock()
    defer { lock.unlock() }
    cancelCallCount += 1
    frameCache.removeValue(forKey: handle.raw)
    readCursor.removeValue(forKey: handle.raw)
  }
}

// MARK: - Synthetic frame data

extension MockSane {
  /// Deterministic, non-uniform test patterns — enough to sanity-check dimensions and
  /// format without needing an exact golden match (the golden-bytes test is specifically
  /// for `FrameDecoder.decodeLineart1`, which unpacks bits it's handed rather than
  /// generating them).
  private static func syntheticFrame(params: SaneParametersRecord) -> [UInt8] {
    let width = Int(params.pixelsPerLine)
    let height = Int(params.lines)
    let bytesPerLine = Int(params.bytesPerLine)
    var data = [UInt8](repeating: 0, count: bytesPerLine * height)

    switch params.format {
    case .rgb:
      fillRGB(&data, width: width, height: height, bytesPerLine: bytesPerLine)
    case .gray where params.depth == 8:
      fillGray8(&data, width: width, height: height, bytesPerLine: bytesPerLine)
    case .gray:
      fillLineart1(&data, width: width, height: height, bytesPerLine: bytesPerLine)
    case .red, .green, .blue:
      break
    }
    return data
  }

  private static func fillRGB(_ data: inout [UInt8], width: Int, height: Int, bytesPerLine: Int) {
    for row in 0..<height {
      for col in 0..<width {
        let base = row * bytesPerLine + col * 3
        data[base] = UInt8(col % 256)
        data[base + 1] = UInt8(row % 256)
        data[base + 2] = UInt8((row + col) % 256)
      }
    }
  }

  private static func fillGray8(_ data: inout [UInt8], width: Int, height: Int, bytesPerLine: Int) {
    for row in 0..<height {
      for col in 0..<width {
        data[row * bytesPerLine + col] = UInt8((row + col) % 256)
      }
    }
  }

  /// 1-bit lineart: deterministic checkerboard, MSB-first packing (1 = black).
  private static func fillLineart1(
    _ data: inout [UInt8], width: Int, height: Int, bytesPerLine: Int
  ) {
    for row in 0..<height {
      for col in 0..<width where (row + col).isMultiple(of: 2) {
        let byteIndex = row * bytesPerLine + col / 8
        let bitIndex = 7 - (col % 8)
        data[byteIndex] |= (1 << bitIndex)
      }
    }
  }
}

// MARK: - Locked helpers (call with `lock` held)

extension MockSane {
  private func currentModeLocked() -> String {
    if case .string(let modeString) = optionValues[OptionIndex.mode.rawValue] {
      return modeString
    }
    return "Gray"
  }

  private func currentDimensionsLocked() -> (width: Int, height: Int) {
    guard case .fixed(let tlX) = optionValues[OptionIndex.topLeftX.rawValue],
      case .fixed(let tlY) = optionValues[OptionIndex.topLeftY.rawValue],
      case .fixed(let brX) = optionValues[OptionIndex.bottomRightX.rawValue],
      case .fixed(let brY) = optionValues[OptionIndex.bottomRightY.rawValue],
      case .int(let dpi) = optionValues[OptionIndex.resolution.rawValue]
    else {
      return (0, 0)
    }
    let widthMM = brX - tlX
    let heightMM = brY - tlY
    let width = Int((widthMM / 25.4 * Double(dpi)).rounded())
    let height = Int((heightMM / 25.4 * Double(dpi)).rounded())
    return (max(width, 0), max(height, 0))
  }
}
