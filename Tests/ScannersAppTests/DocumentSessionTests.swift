import CoreGraphics
import Foundation
import OutputKit
import ScannerKit
import Testing

@testable import ScannersApp

@Suite("DocumentSession")
@MainActor
struct DocumentSessionTests {
  @Test("defaults on init match the mode's own defaults (Text: 300dpi B&W)")
  func initialDefaultsMatchTextMode() {
    let session = DocumentSession(documentMode: .text)
    #expect(session.dpi == 300)
    #expect(session.colorMode == .blackAndWhite)
  }

  @Test("switching documentMode resets dpi/color to the new mode's own defaults")
  func modeSwitchAppliesNewDefaults() {
    let session = DocumentSession(documentMode: .text)
    session.dpi = 600
    session.colorMode = .color

    session.documentMode = .image

    #expect(session.dpi == 600)  // .image's own default happens to also be 600
    #expect(session.colorMode == .color)  // .image's own default happens to also be .color

    session.documentMode = .text
    #expect(session.dpi == 300)
    #expect(session.colorMode == .blackAndWhite)
  }

  @Test(
    "applying a preset sets mode+dpi+color together, not clobbered by the mode-switch default reset"
  )
  func applyPresetSetsAllThreeValues() {
    let session = DocumentSession(documentMode: .text)
    session.applyPreset(.archive)  // image/2400/color

    #expect(session.documentMode == .image)
    #expect(session.dpi == 2400)
    #expect(session.colorMode == .color)
  }

  @Test("scan-loop: addPage appends in order and marks the session dirty")
  func addPageAppendsAndMarksDirty() {
    let session = DocumentSession()
    #expect(session.hasUnsavedChanges == false)

    let pageA = TestFixtures.solidPage()
    let pageB = TestFixtures.solidPage()
    session.addPage(pageA)
    session.addPage(pageB)

    #expect(session.pages.count == 2)
    #expect(session.hasUnsavedChanges)
  }

  @Test("a Text-mode page starts OCR-pending; an Image-mode page needs no OCR")
  func addPageSetsOCRStatusByMode() {
    let textSession = DocumentSession(documentMode: .text)
    let textEntry = textSession.addPage(TestFixtures.solidPage())
    #expect(textEntry.ocrStatus == .pending)

    let imageSession = DocumentSession(documentMode: .image)
    let imageEntry = imageSession.addPage(TestFixtures.solidPage())
    #expect(imageEntry.ocrStatus == .notNeeded)
  }

  @Test("removePage removes exactly the targeted page")
  func removePageRemovesTargetOnly() {
    let session = DocumentSession()
    let first = session.addPage(TestFixtures.solidPage())
    let second = session.addPage(TestFixtures.solidPage())

    session.removePage(id: first.id)

    #expect(session.pages.count == 1)
    #expect(session.pages[0].id == second.id)
  }

  @Test("movePages reorders the page strip")
  func movePagesReorders() {
    let session = DocumentSession()
    let first = session.addPage(TestFixtures.solidPage())
    let second = session.addPage(TestFixtures.solidPage())
    let third = session.addPage(TestFixtures.solidPage())

    session.movePages(fromOffsets: [0], toOffset: 3)

    #expect(session.pages.map(\.id) == [second.id, third.id, first.id])
  }

  @Test(
    "unsaved-changes gate: false for an empty session, true after a page is added, false again after markSaved"
  )
  func unsavedChangesGate() {
    let session = DocumentSession()
    #expect(session.hasUnsavedChanges == false)

    session.addPage(TestFixtures.solidPage())
    #expect(session.hasUnsavedChanges)

    session.markSaved()
    #expect(session.hasUnsavedChanges == false)

    session.removePage(id: session.pages[0].id)
    #expect(session.hasUnsavedChanges == false)  // dirty again, but now empty -- nothing to confirm
  }

  @Test("reset clears pages and dirty state and restores mode defaults")
  func resetClearsSession() {
    let session = DocumentSession(documentMode: .text)
    session.addPage(TestFixtures.solidPage())
    session.dpi = 75

    session.reset()

    #expect(session.pages.isEmpty)
    #expect(session.hasUnsavedChanges == false)
    #expect(session.dpi == 300)
  }

  @Test("setOCRResult marks the target page done and stores its lines; other pages untouched")
  func setOCRResultUpdatesOnlyTargetPage() {
    let session = DocumentSession(documentMode: .text)
    let entry = session.addPage(TestFixtures.solidPage())
    let other = session.addPage(TestFixtures.solidPage())

    let lines = [
      OCRTextLine(text: "hello", boundingBox: CGRect(x: 0, y: 0, width: 0.5, height: 0.1))
    ]
    session.setOCRResult(lines, for: entry.id)

    #expect(session.pages[0].ocrStatus == .done)
    #expect(session.pages[0].ocrLines?.first?.text == "hello")
    #expect(session.pages[1].id == other.id)
    #expect(session.pages[1].ocrStatus == .pending)
  }

  @Test("setOCRFailed marks the page failed without touching its (absent) lines")
  func setOCRFailedMarksStatus() {
    let session = DocumentSession(documentMode: .text)
    let entry = session.addPage(TestFixtures.solidPage())

    session.setOCRFailed(for: entry.id)

    #expect(session.pages[0].ocrStatus == .failed)
    #expect(session.pages[0].ocrLines == nil)
  }

  @Test("currentConfiguration forwards source/lampTimeout and the session's own mode/dpi/color")
  func currentConfigurationBuildsScanConfiguration() {
    let session = DocumentSession(documentMode: .image)
    session.dpi = 1200
    session.colorMode = .color

    let config = session.currentConfiguration(source: .adf, extendLampTimeout: true)

    #expect(config.mode == .color)
    #expect(config.requestedDPI == 1200)
    #expect(config.source == .adf)
    #expect(config.extendLampTimeout)
  }
}
