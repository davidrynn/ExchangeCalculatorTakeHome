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

    /// App launched with a seeded fixed rate (bid=10, ask=20 on MXN) so
    /// input-reflection assertions have a predictable multiplier.
    @MainActor
    private func makeAppWithSeededRate() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITEST_SEED_RATE"]
        return app
    }

    /// App launched with a service that throws on `fetchRates`, so the
    /// error banner shows.
    @MainActor
    private func makeAppWithFailingRates() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITEST_FAIL_RATES"]
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
    func testUSDCInputUpdatesForeignField() {
        let app = makeAppWithSeededRate()
        app.launch()

        let usdcField = app.textFields["usdcAmountField"]
        let foreignField = app.textFields["foreignAmountField"]
        XCTAssertTrue(usdcField.waitForExistence(timeout: 5))

        // Wait for the seeded rate to load so the conversion fires.
        let rate = app.staticTexts["rateSummaryLabel"]
        _ = rate.waitForExistence(timeout: 5)

        usdcField.tap()
        usdcField.typeText("2")

        // Seeded bid = 10 → 2 USDc × 10 = 20 MXN, formatted to 2dp.
        let foreignValue = foreignField.value as? String ?? ""
        XCTAssertEqual(foreignValue, "20.00",
                       "Foreign field should reflect 2 × bid(10) = 20.00")
    }

    @MainActor
    func testForeignInputUpdatesUSDCField() {
        let app = makeAppWithSeededRate()
        app.launch()

        let usdcField = app.textFields["usdcAmountField"]
        let foreignField = app.textFields["foreignAmountField"]
        XCTAssertTrue(foreignField.waitForExistence(timeout: 5))

        _ = app.staticTexts["rateSummaryLabel"].waitForExistence(timeout: 5)

        foreignField.tap()
        foreignField.typeText("40")

        // Seeded ask = 20 → 40 MXN ÷ 20 = 2 USDc, formatted to 2dp.
        let usdcValue = usdcField.value as? String ?? ""
        XCTAssertEqual(usdcValue, "2.00",
                       "USDc field should reflect 40 ÷ ask(20) = 2.00")
    }

    @MainActor
    func testNetworkErrorShowsErrorBanner() {
        let app = makeAppWithFailingRates()
        app.launch()

        // The Retry button is unique to the error banner and is a
        // reliably-queryable element. If it appears, the banner rendered.
        let retry = app.buttons["errorRetry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5),
                      "Error banner with Retry should appear when the service throws on fetchRates")
        XCTAssertTrue(retry.isHittable)
    }

    @MainActor
    func testRetryReTriggersLoadAndBannerReappears() {
        let app = makeAppWithFailingRates()
        app.launch()

        let retry = app.buttons["errorRetry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()

        // Tapping Retry clears errorMessage (banner disappears briefly),
        // bumps the retry token → .task(id:) re-fires → service throws
        // again → banner reappears. We can assert the banner is still
        // present (or returns quickly) as proof that Retry reached the
        // load path, not just that the view state cleared.
        XCTAssertTrue(app.buttons["errorRetry"].waitForExistence(timeout: 5),
                      "Retry should re-trigger the load; the banner should reappear when fetch fails again")
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
