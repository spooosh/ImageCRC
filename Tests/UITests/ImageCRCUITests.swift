import XCTest

final class ImageCRCHappyPathTests: XCTestCase {
    private var tempDirURL: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        let base = FileManager.default.temporaryDirectory
        tempDirURL = base.appendingPathComponent("imagecrc-uitest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
        let outputDir = tempDirURL.appendingPathComponent("out", isDirectory: true)

        app = XCUIApplication()
        app.launchEnvironment["IMAGECRC_UI_TEST"] = "1"
        app.launchArguments = [
            "--ui-test-output-dir", outputDir.path,
            "--ui-test-preload-files", "2",
        ]
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if let url = tempDirURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testHappyPathFromPreloadedFilesToCompletionSheet() throws {
        app.launch()

        let dropZone = app.descendants(matching: .any)["dropZone"]
        XCTAssertTrue(dropZone.waitForExistence(timeout: 10),
                      "dropZone must be in the AX tree within 10s of launch")

        let startButton = app.descendants(matching: .any)["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10),
                      "startButton must exist")
        let startEnabledExp = expectation(for: NSPredicate(format: "isEnabled == true"),
                                          evaluatedWith: startButton)
        wait(for: [startEnabledExp], timeout: 10)

        startButton.tap()

        let completionSheet = app.descendants(matching: .any)["completionSheet"]
        XCTAssertTrue(completionSheet.waitForExistence(timeout: 30),
                      "completionSheet must appear within 30s of start tap")

        let dismiss = app.descendants(matching: .any)["dismissButton"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 10))
        dismiss.tap()

        let sheetGoneExp = expectation(for: NSPredicate(format: "exists == false"),
                                       evaluatedWith: completionSheet)
        wait(for: [sheetGoneExp], timeout: 10)

        XCTAssertTrue(dropZone.exists, "dropZone must remain visible after dismiss")

        let outputDir = tempDirURL.appendingPathComponent("out")
        let outputs = try FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil)
        let jpgCount = outputs.filter { $0.pathExtension.lowercased() == "jpg" }.count
        XCTAssertGreaterThanOrEqual(jpgCount, 1, "at least one JPG must land in the output dir")
        XCTAssertLessThanOrEqual(jpgCount, 2, "at most two JPGs (one per preloaded file)")
    }
}

// ImageCRCCancelFlowTests was attempted in T6 but proved fundamentally racy on
// Apple Silicon. Even with 64 × 4096px gradient PNGs and an off-main preload,
// the JPEG q=80 batch finishes within the 250ms AX poll interval window often
// enough that the progressOverlay either never appears in the AX tree or
// vanishes before XCUITest can latch onto it. Removing `.transition(...)` from
// ProgressOverlayView made the overlay queryable but the cancel button inside
// it remained invisible — a SwiftUI/AppKit AX quirk we couldn't pin down
// without production-code changes that hurt the visual UX.
//
// Deferred deliberately. Cancel-flow at the converter level is already covered
// by IntegrationTests/ImageConverterCancelTests. The UI-side cancel path is
// trivial wiring to viewModel.cancel(), exercised manually during dev.
//
// To bring it back, options include: AVIF output (10× slower than JPEG —
// reliably observable), an env-flag that lets tests inject artificial work,
// or a SwiftUI redesign where the overlay is always mounted with .opacity
// instead of conditional render.
