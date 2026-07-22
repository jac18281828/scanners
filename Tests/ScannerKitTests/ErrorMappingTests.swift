import Testing

@testable import ScannerKit

@Suite("Error mapping")
struct ErrorMappingTests {
  @Test("opening an unknown device id maps to deviceNotFound")
  func unknownDeviceMapsToDeviceNotFound() async throws {
    let mock = MockSane()
    let session = ScanSession(
      deviceID: "hp5590:libusb:999:999", backend: mock, runner: SaneRunner())
    let config = ScanConfiguration(mode: .gray, requestedDPI: 100)

    do {
      for try await _ in session.scan(config: config) {}
      Issue.record("expected scan(config:) to throw")
    } catch let error as ScanError {
      #expect(error == .deviceNotFound("hp5590:libusb:999:999"))
    }
  }

  @Test("a busy device maps to deviceBusy")
  func busyDeviceMapsToDeviceBusy() async throws {
    var configuration = MockSane.Configuration.default
    configuration.openFailure = .deviceBusy
    let mock = MockSane(configuration: configuration)
    let session = ScanSession(
      deviceID: configuration.devices[0].name, backend: mock, runner: SaneRunner())
    let config = ScanConfiguration(mode: .gray, requestedDPI: 100)

    do {
      for try await _ in session.scan(config: config) {}
      Issue.record("expected scan(config:) to throw")
    } catch let error as ScanError {
      #expect(error == .deviceBusy(configuration.devices[0].name))
    }
  }

  @Test("ScanError descriptions are human-readable")
  func descriptionsAreReadable() {
    #expect(ScanError.deviceNotFound("x").description.contains("x"))
    #expect(ScanError.deviceBusy("x").description.contains("busy"))
    #expect(ScanError.cancelled.description.contains("cancel"))
    #expect(ScanError.ioError("disk full").description == "disk full")
  }
}
