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

        // Seed both fields with distinct values. Without a loaded rate
        // (rate loading lands in Phase 5), typing into USDc does not
        // auto-fill foreign — so we type into each field independently.
        usdcField.tap()
        usdcField.typeText("11")

        foreignField.tap()
        foreignField.typeText("22")

        let beforeSwapUSDc = (usdcField.value as? String) ?? ""
        let beforeSwapForeign = (foreignField.value as? String) ?? ""
        XCTAssertEqual(beforeSwapUSDc, "11")
        XCTAssertEqual(beforeSwapForeign, "22")

        app.buttons["swapButton"].tap()

        let afterSwapUSDc = (usdcField.value as? String) ?? ""
        let afterSwapForeign = (foreignField.value as? String) ?? ""
        XCTAssertEqual(afterSwapUSDc, "22", "USDc should now hold the prior foreign value")
        XCTAssertEqual(afterSwapForeign, "11", "Foreign should now hold the prior USDc value")
    }
}
