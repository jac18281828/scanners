import Testing

@testable import ScannersApp

@Suite("ImageSaveName")
struct ImageSaveNameTests {
  @Test("a name already ending in a known image extension has it replaced")
  func replacesKnownExtension() {
    #expect(
      ImageSaveName.applyingExtension(
        ImageFormat.png.fileExtension, toTypedName: "receipt-acme.jpg")
        == "receipt-acme.png")
  }

  @Test("the known-extension match is case-insensitive")
  func matchIsCaseInsensitive() {
    #expect(
      ImageSaveName.applyingExtension(ImageFormat.jpeg.fileExtension, toTypedName: "Scan.TIFF")
        == "Scan.jpg")
  }

  @Test("a dot that isn't a known image extension is left alone and the new extension appended")
  func appendsWhenNoKnownExtension() {
    #expect(
      ImageSaveName.applyingExtension(ImageFormat.png.fileExtension, toTypedName: "Invoice No. 5")
        == "Invoice No. 5.png")
  }

  @Test("a name with no dot at all gains the extension")
  func appendsWhenNoDot() {
    #expect(
      ImageSaveName.applyingExtension(ImageFormat.png.fileExtension, toTypedName: "Invoice")
        == "Invoice.png")
  }
}
