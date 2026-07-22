import Testing

@testable import ScannerKit

@Suite("Option negotiation")
struct OptionNegotiationTests {
  private func makeSession(mock: MockSane) -> ScanSession {
    ScanSession(
      deviceID: MockSane.Configuration.default.devices[0].name, backend: mock, runner: SaneRunner())
  }

  @Test("mode, source, and resolution are set to the requested values")
  func setsModeSourceResolution() async throws {
    let mock = MockSane()
    let session = makeSession(mock: mock)
    let config = ScanConfiguration(mode: .color, requestedDPI: 300, source: .flatbed)

    var sawStarted: ScanParametersInfo?
    for try await event in session.scan(config: config) {
      if case .started(let info) = event {
        sawStarted = info
      }
    }

    let info = try #require(sawStarted)
    #expect(info.hardwareDPI == 300)
    #expect(info.requestedDPI == 300)
    #expect(info.mode == .color)
  }

  @Test(
    "a non-native dpi request is snapped up by ResolutionPolicy before ever reaching the device")
  func nonNativeRequestSnapsUp() async throws {
    let mock = MockSane()
    let session = makeSession(mock: mock)
    // 150 isn't native; ResolutionPolicy snaps it to 200 before setOption is ever called,
    // so the well-behaved mock (whose word list matches ResolutionPolicy.nativeDPI exactly)
    // accepts it exactly — no SANE_INFO_INEXACT involved in this path.
    let config = ScanConfiguration(mode: .gray, requestedDPI: 150)

    var sawStarted: ScanParametersInfo?
    for try await event in session.scan(config: config) {
      if case .started(let info) = event {
        sawStarted = info
      }
    }

    let info = try #require(sawStarted)
    #expect(info.requestedDPI == 150)
    #expect(info.hardwareDPI == 200)
  }

  @Test(
    "SANE_INFO_INEXACT: when the simulated hardware's own dpi set diverges from ResolutionPolicy, the readback wins"
  )
  func hardwareInexactReadbackWins() async throws {
    // Hardware that doesn't actually support 300dpi (unlike the real 4570c) — forces the
    // mock to snap internally and report SANE_INFO_INEXACT. ScanSession must trust the
    // value it reads back afterward, not the candidate it originally asked for.
    var configuration = MockSane.Configuration.default
    configuration.supportedDPI = [100, 200, 600, 1200, 2400]
    let mock = MockSane(configuration: configuration)
    let session = makeSession(mock: mock)
    let config = ScanConfiguration(mode: .gray, requestedDPI: 300)

    var sawStarted: ScanParametersInfo?
    for try await event in session.scan(config: config) {
      if case .started(let info) = event {
        sawStarted = info
      }
    }

    let info = try #require(sawStarted)
    #expect(info.requestedDPI == 300)
    // Mock snaps 300 to the nearest of [100,200,600,1200,2400] by absolute distance: 200.
    #expect(info.hardwareDPI == 200)
  }

  @Test("full-bed default area spans the device's reported geometry")
  func fullBedDefaultArea() async throws {
    let mock = MockSane()
    let session = makeSession(mock: mock)
    let config = ScanConfiguration(mode: .gray, requestedDPI: 100, area: nil)

    var sawStarted: ScanParametersInfo?
    for try await event in session.scan(config: config) {
      if case .started(let info) = event {
        sawStarted = info
      }
    }

    let info = try #require(sawStarted)
    let bed = MockSane.Configuration.default
    let expectedWidthPixels = Int((bed.bedWidthMM / 25.4 * 100).rounded())
    let expectedHeightPixels = Int((bed.bedHeightMM / 25.4 * 100).rounded())
    #expect(info.widthPixels == expectedWidthPixels)
    #expect(info.heightPixels == expectedHeightPixels)
  }

  @Test("a custom sub-area is honored")
  func customSubArea() async throws {
    let mock = MockSane()
    let session = makeSession(mock: mock)
    let area = ScanArea(topLeftXMM: 10, topLeftYMM: 10, widthMM: 50.8, heightMM: 25.4)
    let config = ScanConfiguration(mode: .gray, requestedDPI: 100, area: area)

    var sawStarted: ScanParametersInfo?
    for try await event in session.scan(config: config) {
      if case .started(let info) = event {
        sawStarted = info
      }
    }

    let info = try #require(sawStarted)
    // 50.8mm @ 100dpi = 200px, 25.4mm @ 100dpi = 100px.
    #expect(info.widthPixels == 200)
    #expect(info.heightPixels == 100)
  }
}
