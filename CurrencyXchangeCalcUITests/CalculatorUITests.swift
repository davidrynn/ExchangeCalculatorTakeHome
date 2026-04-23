import XCTest

final class CalculatorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        // Deterministic: no live rate load, no network race.
        app.launchArguments += ["-UITEST_DISABLE_NETWORK"]
        return app
    }

    @MainActor
    func testCalculatorLoads() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["exchangeTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["usdcAmountField"].exists)
        XCTAssertTrue(app.textFields["foreignAmountField"].exists)
        XCTAssertTrue(app.buttons["swapButton"].exists)
    }

    @MainActor
    func testSwapButtonExists() {
        let app = makeApp()
        app.launch()

        let swap = app.buttons["swapButton"]
        XCTAssertTrue(swap.waitForExistence(timeout: 5))
        XCTAssertTrue(swap.isHittable)
    }

    @MainActor
    func testSwapButtonSwapsRowPositions() {
        let app = makeApp()
        app.launch()

        let usdcField = app.textFields["usdcAmountField"]
        let foreignField = app.textFields["foreignAmountField"]
        XCTAssertTrue(usdcField.waitForExistence(timeout: 5))
        XCTAssertTrue(foreignField.exists)

        // Initially, USDc is on top (smaller Y) and foreign is below it.
        let initialUSDcY = usdcField.frame.minY
        let initialForeignY = foreignField.frame.minY
        XCTAssertLessThan(initialUSDcY, initialForeignY,
                          "USDc row should start above the foreign row")

        // Seed each field with a value; swap must not touch the values.
        usdcField.tap()
        usdcField.typeText("11")
        foreignField.tap()
        foreignField.typeText("22")

        app.buttons["swapButton"].tap()

        // Positions inverted: foreign row is now above USDc row.
        let swappedUSDcY = app.textFields["usdcAmountField"].frame.minY
        let swappedForeignY = app.textFields["foreignAmountField"].frame.minY
        XCTAssertGreaterThan(swappedUSDcY, swappedForeignY,
                             "After swap, foreign row should be above USDc row")

        // Values stay attached to their rows.
        XCTAssertEqual(app.textFields["usdcAmountField"].value as? String, "11",
                       "USDc amount stays with USDc row across a swap")
        XCTAssertEqual(app.textFields["foreignAmountField"].value as? String, "22",
                       "Foreign amount stays with foreign row across a swap")
    }
}
