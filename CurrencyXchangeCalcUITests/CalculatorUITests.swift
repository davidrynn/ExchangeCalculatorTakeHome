import XCTest

final class CalculatorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCalculatorLoads() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["exchangeTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["usdcAmountField"].exists)
        XCTAssertTrue(app.textFields["foreignAmountField"].exists)
        XCTAssertTrue(app.buttons["swapButton"].exists)
    }

    @MainActor
    func testSwapButtonExists() {
        let app = XCUIApplication()
        app.launch()

        let swap = app.buttons["swapButton"]
        XCTAssertTrue(swap.waitForExistence(timeout: 5))
        XCTAssertTrue(swap.isHittable)
    }

    @MainActor
    func testSwapButtonSwapsValues() {
        let app = XCUIApplication()
        app.launch()

        let usdcField = app.textFields["usdcAmountField"]
        let foreignField = app.textFields["foreignAmountField"]
        XCTAssertTrue(usdcField.waitForExistence(timeout: 5))

        // Seed the two fields with distinct values via direct typing.
        // We rely on each field's accessibility value for assertions.
        usdcField.tap()
        usdcField.typeText("5")

        app.buttons["swapButton"].tap()

        // After swap, the USDc field's value now contains what was in
        // foreign, and vice-versa. We don't assert exact arithmetic here;
        // exact math is covered by ViewModel unit tests.
        let swappedUSDc = (usdcField.value as? String) ?? ""
        let swappedForeign = (foreignField.value as? String) ?? ""
        XCTAssertNotEqual(swappedUSDc, "5", "USDc should no longer hold its original value after swap")
        // Either field holding "5" is acceptable depending on where the
        // pre-swap value landed; we just need one of them to reflect it.
        XCTAssertTrue(swappedUSDc == "5" || swappedForeign == "5",
                      "Original '5' should appear in one of the two fields after swap")
    }
}
