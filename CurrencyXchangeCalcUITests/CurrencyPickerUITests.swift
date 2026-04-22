import XCTest

final class CurrencyPickerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPickerOpensOnForeignCurrencyTap() {
        let app = XCUIApplication()
        app.launch()

        let foreignPicker = app.buttons["foreignCurrencyPicker"]
        XCTAssertTrue(foreignPicker.waitForExistence(timeout: 5))
        foreignPicker.tap()

        XCTAssertTrue(
            app.otherElements["currencyPickerSheet"].waitForExistence(timeout: 3)
                || app.buttons["currencyPickerRow.MXN"].waitForExistence(timeout: 3),
            "Currency picker sheet should appear after tapping the foreign currency label"
        )
    }

    @MainActor
    func testPickerDismissesViaCancel() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["foreignCurrencyPicker"].tap()
        XCTAssertTrue(app.buttons["currencyPickerCancel"].waitForExistence(timeout: 3))
        app.buttons["currencyPickerCancel"].tap()

        XCTAssertFalse(
            app.buttons["currencyPickerRow.MXN"].waitForExistence(timeout: 1),
            "Picker rows should not be visible after cancel"
        )
    }

    @MainActor
    func testSelectingCurrencyUpdatesFieldAndDismissesPicker() {
        let app = XCUIApplication()
        app.launch()

        let foreignPicker = app.buttons["foreignCurrencyPicker"]
        XCTAssertTrue(foreignPicker.waitForExistence(timeout: 5))
        // Initial label reflects MXN (the first fallback currency).
        XCTAssertTrue(foreignPicker.label.contains("MXN"))

        foreignPicker.tap()
        let arsRow = app.buttons["currencyPickerRow.ARS"]
        XCTAssertTrue(arsRow.waitForExistence(timeout: 3))
        arsRow.tap()

        // Picker dismissed, original button label now reflects ARS.
        XCTAssertFalse(arsRow.waitForExistence(timeout: 1))
        // Allow the foreign label to update.
        let updatedForeign = app.buttons["foreignCurrencyPicker"]
        XCTAssertTrue(updatedForeign.waitForExistence(timeout: 3))
        XCTAssertTrue(updatedForeign.label.contains("ARS"),
                      "Foreign picker label should reflect the newly-selected currency (ARS)")
    }
}
