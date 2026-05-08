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

final class ImageCRCCancelFlowTests: XCTestCase {
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
        // 8 files at 4096x4096 take real wall-clock time to decode/encode —
        // cancel tap reliably lands before the batch finishes. Task.isCancelled
        // checks in ImageConverter.processOne short-circuit work in progress.
        app.launchArguments = [
            "--ui-test-output-dir", outputDir.path,
            "--ui-test-preload-files", "8",
            "--ui-test-preload-size", "4096",
        ]
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if let url = tempDirURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testCancelMidBatchReachesCompletionSheetWithFewerOutputs() throws {
        app.launch()

        let startButton = app.descendants(matching: .any)["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 30),
                      "startButton must exist (preload of 8x 4096px PNGs may be slow on first launch)")
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"),
                                  evaluatedWith: startButton)
        wait(for: [enabled], timeout: 30)
        startButton.tap()

        let cancelButton = app.descendants(matching: .any)["cancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 10),
                      "cancelButton must appear once a slow batch is running")
        cancelButton.tap()

        let completionSheet = app.descendants(matching: .any)["completionSheet"]
        XCTAssertTrue(completionSheet.waitForExistence(timeout: 60),
                      "completionSheet must still appear after cancel tap")

        let dismiss = app.descendants(matching: .any)["dismissButton"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 10))
        dismiss.tap()

        let outputDir = tempDirURL.appendingPathComponent("out")
        let outputs = (try? FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil)) ?? []
        let jpgCount = outputs.filter { $0.pathExtension.lowercased() == "jpg" }.count
        XCTAssertLessThan(jpgCount, 8,
                          "cancel must short-circuit some files; output dir had \(jpgCount) of 8")
    }
}
