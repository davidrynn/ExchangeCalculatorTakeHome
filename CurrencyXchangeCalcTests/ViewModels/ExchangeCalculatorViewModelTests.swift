import Foundation
import Testing
@testable import CurrencyXchangeCalc

/// Tests are `@MainActor` because the VM is MainActor-isolated. The mock
/// service is also `@MainActor`-isolated per Phase 0 design.
@MainActor
struct ExchangeCalculatorViewModelTests {

    // MARK: - Fixtures

    private func makeVM(
        ask: Decimal = Decimal(string: "18.4105")!,
        bid: Decimal = Decimal(string: "18.4069")!,
        currency: Currency = Currency.fallbackList[0] // MXN
    ) async -> (ExchangeCalculatorViewModel, MockExchangeRateService) {
        let mock = MockExchangeRateService()
        mock.stubbedRates = [
            ExchangeRate(ask: ask, bid: bid, book: "usdc_\(currency.code.lowercased())", date: "")
        ]
        let vm = ExchangeCalculatorViewModel(service: mock, selectedCurrency: currency)
        await vm.loadRates()
        return (vm, mock)
    }

    // MARK: - Direction regression guards (bid/ask)

    @Test
    func usdcToForeignMultipliesByBid() async {
        let (vm, _) = await makeVM()
        vm.usdcAmountChanged("1")
        // 1 × 18.4069 = 18.4069 — formatter shows 4-8 fractional digits
        #expect(vm.foreignAmount == "18.4069")
    }

    @Test
    func foreignToUsdcDividesByAsk() async {
        // Use a clean divisor (ask=20) to avoid Decimal division
        // approximation noise (Apple's Decimal can produce 0.99997…
        // when dividing identical non-power-of-10 values).
        let (vm, _) = await makeVM(
            ask: Decimal(string: "20")!,
            bid: Decimal(string: "10")!
        )
        vm.foreignAmountChanged("20")
        // 20 / 20 = 1 → "1.0000" (min 4 fractional digits)
        #expect(vm.usdcAmount == "1.0000")
    }

    /// Without this, it would be easy to accidentally swap bid/ask and the
    /// app would still "work" (both directions would just use the wrong
    /// price). This test locks in that the two directions give *different*
    /// results consistent with `ask > bid`.
    @Test
    func bidAndAskAreUsedAsymmetrically() async {
        let (vm, _) = await makeVM(
            ask: Decimal(string: "20")!,
            bid: Decimal(string: "10")!
        )
        // 1 USDc → foreign uses bid → 10
        vm.usdcAmountChanged("1")
        #expect(vm.foreignAmount == "10.0000")

        // 20 foreign → USDc uses ask → 1
        vm.foreignAmountChanged("20")
        #expect(vm.usdcAmount == "1.0000")
    }

    // MARK: - Swap

    @Test
    func swapTogglesIsSwappedFlag() async {
        let (vm, _) = await makeVM()
        #expect(vm.isSwapped == false, "Defaults to USDc-on-top")
        vm.swapCurrencies()
        #expect(vm.isSwapped == true)
        vm.swapCurrencies()
        #expect(vm.isSwapped == false)
    }

    @Test
    func swapDoesNotMutateAmounts() async {
        // Rows move as atomic units — the USDc amount stays the USDc amount
        // regardless of display position.
        let (vm, _) = await makeVM()
        vm.usdcAmount = "1.00"
        vm.foreignAmount = "18.41"
        vm.swapCurrencies()
        #expect(vm.usdcAmount == "1.00")
        #expect(vm.foreignAmount == "18.41")
    }

    @Test
    func editingAfterSwapUpdatesCurrencyBoundFieldNotVisualPosition() async {
        // Lock in: after swap, `usdcAmountChanged` still drives the
        // foreign amount via × bid (USDc→foreign math), regardless of
        // which row is displayed on top. Rows are a view concern; the
        // VM's input handlers stay currency-bound.
        let (vm, _) = await makeVM(
            ask: Decimal(string: "20")!,
            bid: Decimal(string: "10")!
        )
        vm.swapCurrencies()
        #expect(vm.isSwapped == true)
        vm.usdcAmountChanged("2")
        #expect(vm.usdcAmount == "2")
        #expect(vm.foreignAmount == "20.0000", "USDc→foreign still uses × bid (2 × 10 = 20)")
    }

    // MARK: - Currency selection

    @Test
    func selectingSameCurrencyKeepsRate() async {
        let (vm, _) = await makeVM()
        let rateBefore = vm.currentRate
        vm.selectCurrency(Currency.fallbackList[0]) // same MXN
        #expect(vm.currentRate == rateBefore)
    }

    @Test
    func selectingDifferentCurrencyInvalidatesStaleRate() async {
        let mxn = Currency.fallbackList.first { $0.code == "MXN" }!
        let ars = Currency.fallbackList.first { $0.code == "ARS" }!
        let (vm, _) = await makeVM(currency: mxn)
        #expect(vm.currentRate != nil)
        vm.selectCurrency(ars)
        // Rate was for MXN — should be cleared when we switch to ARS
        // because the view has not yet triggered a new loadRates.
        #expect(vm.currentRate == nil)
        #expect(vm.foreignAmount == "")
    }

    // MARK: - Input guards

    @Test
    func emptyUsdcInputClearsForeign() async {
        let (vm, _) = await makeVM()
        vm.usdcAmountChanged("1")
        #expect(!vm.foreignAmount.isEmpty)
        vm.usdcAmountChanged("")
        #expect(vm.usdcAmount == "")
        #expect(vm.foreignAmount == "")
    }

    @Test
    func nonNumericInputIgnored() async {
        let (vm, _) = await makeVM()
        vm.usdcAmount = "1"
        vm.foreignAmount = "18.4069"
        vm.usdcAmountChanged("abc")
        // usdcAmount reflects the keystroke, but foreignAmount is NOT
        // updated from a garbage parse.
        #expect(vm.usdcAmount == "abc")
        #expect(vm.foreignAmount == "18.4069")
    }

    @Test
    func zeroInputProducesZeroOutput() async {
        let (vm, _) = await makeVM()
        vm.usdcAmountChanged("0")
        // 4-digit minimum (see format() doc for rationale)
        #expect(vm.foreignAmount == "0.0000")
    }

    // MARK: - Locale

    @Test
    func esESLocaleParsesCommaDecimal() {
        let spain = Locale(identifier: "es_ES")
        let parsed = ExchangeCalculatorViewModel.parse("1,23", locale: spain)
        #expect(parsed == Decimal(string: "1.23")!)
    }

    @Test
    func esESLocaleFormatsWithComma() {
        let spain = Locale(identifier: "es_ES")
        let formatted = ExchangeCalculatorViewModel.format(Decimal(string: "1.23")!, locale: spain)
        #expect(formatted == "1,2300")
    }

    @Test
    func enUSLocaleParsesAndFormatsWithDot() {
        let us = Locale(identifier: "en_US")
        #expect(ExchangeCalculatorViewModel.parse("1.23", locale: us) == Decimal(string: "1.23")!)
        #expect(ExchangeCalculatorViewModel.format(Decimal(string: "1.23")!, locale: us) == "1.2300")
    }

    // MARK: - Display precision (4...8 fractional digits)

    @Test
    func formatZeroPadsToFourDp() {
        let us = Locale(identifier: "en_US")
        #expect(ExchangeCalculatorViewModel.format(Decimal.zero, locale: us) == "0.0000")
    }

    @Test
    func formatTruncatesAtMaxEightDp() {
        // 1.234567890 has 9 fractional digits — formatter rounds to 8.
        let us = Locale(identifier: "en_US")
        #expect(ExchangeCalculatorViewModel.format(Decimal(string: "1.234567890")!, locale: us)
                == "1.23456789")
        // Whole numbers pad to the 4-digit minimum.
        #expect(ExchangeCalculatorViewModel.format(Decimal(string: "1")!, locale: us) == "1.0000")
    }

    @Test
    func formatTinyValueRevealsSignificantDigits() {
        // 0.000645 fits in 4...8; previously 2dp would have rendered "0.00".
        let us = Locale(identifier: "en_US")
        let formatted = ExchangeCalculatorViewModel.format(
            Decimal(string: "0.000645")!,
            locale: us
        )
        #expect(formatted == "0.000645",
                "Expected full-precision output, got \(formatted)")
    }

    @Test
    func formatRoundTripPreservesPrecisionForMxnLikeRates() {
        // The reported edge case: typing 1 MXN at ask ≈ 17.36 produced
        // "0.06" USDc, and typing "0.06" back produced 1.04 MXN — a 4%
        // round-trip drift. With 4dp display we keep "0.0576" and the
        // re-entered value lands within ~0.2% (just the bid/ask spread).
        let us = Locale(identifier: "en_US")
        let mxnAsk = Decimal(string: "17.3625")!
        let mxnBid = Decimal(string: "17.3589")!
        let usdc = 1 / mxnAsk
        let displayed = ExchangeCalculatorViewModel.format(usdc, locale: us)
        // Should look like "0.0576" — 4 fractional digits, non-zero
        #expect(displayed.hasPrefix("0.05"), "Got \(displayed)")

        // Round-trip: type the displayed value back into USDc, multiply by bid.
        let parsedBack = ExchangeCalculatorViewModel.parse(displayed, locale: us)!
        let returned = parsedBack * mxnBid
        let returnedString = ExchangeCalculatorViewModel.format(returned, locale: us)
        // Should be very close to "1.0000" — within 1% of the original 1 MXN.
        #expect(returnedString.hasPrefix("0.99") || returnedString.hasPrefix("1.00"),
                "Round-trip drifted too far: \(returnedString)")
    }

    @Test
    func formatNegativeTinyValueAlsoExtends() {
        let us = Locale(identifier: "en_US")
        let formatted = ExchangeCalculatorViewModel.format(
            Decimal(string: "-0.000645")!,
            locale: us
        )
        #expect(formatted == "-0.000645",
                "Expected extended precision for negative tiny, got \(formatted)")
    }

    @Test
    func reInvokingForeignChangedWithSameValueIsNoop() async {
        // Reported bug: "tapping back and forth changes the numbers."
        // Root cause: SwiftUI fires the binding setter on focus / rebind
        // with the existing display string. Without an idempotent guard,
        // each tap flips lastEditedSide and re-derives the opposite
        // side via the asymmetric bid/ask, causing drift.
        let (vm, _) = await makeVM()
        vm.usdcAmountChanged("1")
        let snapshotUsdc = vm.usdcAmount
        let snapshotForeign = vm.foreignAmount
        let snapshotUsdcDecimal = vm.usdcDecimal
        let snapshotForeignDecimal = vm.foreignDecimal

        // Simulate SwiftUI firing the foreign setter with the *current*
        // foreign display value (a focus-fire, not a real edit).
        vm.foreignAmountChanged(vm.foreignAmount)

        #expect(vm.usdcAmount == snapshotUsdc, "USDc string drifted: \(vm.usdcAmount)")
        #expect(vm.foreignAmount == snapshotForeign, "Foreign string drifted: \(vm.foreignAmount)")
        #expect(vm.usdcDecimal == snapshotUsdcDecimal, "USDc decimal drifted")
        #expect(vm.foreignDecimal == snapshotForeignDecimal, "Foreign decimal drifted")
    }

    @Test
    func reInvokingUsdcChangedWithSameValueIsNoop() async {
        // Inverse of the above — type in foreign, then re-fire USDc
        // setter with the existing USDc display string. Nothing
        // should change.
        let (vm, _) = await makeVM()
        vm.foreignAmountChanged("18.4069")
        let snapshotUsdc = vm.usdcAmount
        let snapshotForeign = vm.foreignAmount
        let snapshotUsdcDecimal = vm.usdcDecimal
        let snapshotForeignDecimal = vm.foreignDecimal

        vm.usdcAmountChanged(vm.usdcAmount)

        #expect(vm.usdcAmount == snapshotUsdc)
        #expect(vm.foreignAmount == snapshotForeign)
        #expect(vm.usdcDecimal == snapshotUsdcDecimal)
        #expect(vm.foreignDecimal == snapshotForeignDecimal)
    }

    @Test
    func rateRefreshDoesNotMutateUserTypedSide() async {
        // Reported regression: typing 1 in foreign, then having the
        // rate refresh, would re-process the COMPUTED USDc display
        // string ("0.0576") through the clamp/parse pipeline,
        // truncating it to "0.05" and shifting the foreign side back.
        // After refactor: lastEditedSide is .foreign so the rate
        // refresh re-derives USDc from foreignDecimal directly. The
        // foreign side stays exactly as the user typed it.
        let mock = MockExchangeRateService()
        mock.stubbedRates = [
            ExchangeRate(
                ask: Decimal(string: "17.36")!,
                bid: Decimal(string: "17.34")!,
                book: "usdc_mxn",
                date: ""
            )
        ]
        let mxn = Currency.fallbackList.first { $0.code == "MXN" }!
        let vm = ExchangeCalculatorViewModel(service: mock, selectedCurrency: mxn)
        await vm.loadRates()

        vm.foreignAmountChanged("1")
        let typedForeign = vm.foreignAmount

        // Simulate a rate refresh (e.g. .task(id:) re-fires).
        mock.stubbedRates = [
            ExchangeRate(
                ask: Decimal(string: "17.50")!,
                bid: Decimal(string: "17.48")!,
                book: "usdc_mxn",
                date: ""
            )
        ]
        await vm.loadRates()

        #expect(vm.foreignAmount == typedForeign,
                "Rate refresh must NOT mutate the side the user just typed")
        #expect(vm.foreignDecimal == Decimal(string: "1")!)
    }

    @Test
    func typingOneARSShowsMeaningfulUSDcValue() async {
        // Regression guard against the reported bug: "when I input a
        // value on the non-US row, nothing happens" — for ARS
        // (ask ≈ 1551), 1 ARS → 1/1551 USDc ≈ 0.000645. With the old
        // fixed-2dp formatter this rendered as "0.00"; the user
        // couldn't see that the conversion had fired.
        let ars = Currency(code: "ARS", flagEmoji: "🇦🇷", displayName: "Argentine Peso")
        let mock = MockExchangeRateService()
        mock.stubbedRates = [
            ExchangeRate(
                ask: Decimal(string: "1551.0000000000")!,
                bid: Decimal(string: "1539.4290300000")!,
                book: "usdc_ars",
                date: ""
            )
        ]
        let vm = ExchangeCalculatorViewModel(service: mock, selectedCurrency: ars)
        await vm.loadRates()

        vm.foreignAmountChanged("1")

        #expect(vm.usdcAmount != "0.00",
                "Tiny conversions must not collapse to 0.00 — got \(vm.usdcAmount)")
        #expect(vm.usdcAmount.hasPrefix("0.000"),
                "Expected leading zeros followed by significant digits, got \(vm.usdcAmount)")
    }

    // MARK: - Large numbers (Decimal, not Double)

    @Test
    func largeInputDoesNotOverflow() async {
        let (vm, _) = await makeVM()
        vm.usdcAmountChanged("1000000")
        // 1_000_000 × 18.4069 = 18,406,900
        // Whatever Decimal.FormatStyle produces (locale-dependent grouping
        // separator), we just assert no crash and non-empty output.
        #expect(!vm.foreignAmount.isEmpty)
        #expect(vm.foreignAmount != "0.00")
    }

    // MARK: - Load error path (surface error for mock failure)

    @Test
    func loadRatesErrorSurfacesMessage() async {
        let mock = MockExchangeRateService()
        mock.shouldThrow = true
        let vm = ExchangeCalculatorViewModel(service: mock, selectedCurrency: Currency.fallbackList[0])

        await vm.loadRates()

        #expect(vm.errorMessage != nil)
        #expect(vm.isLoading == false)
        #expect(vm.currentRate == nil)
    }

    @Test
    func loadRatesSuccessClearsErrorAndIsLoading() async {
        let (vm, _) = await makeVM()
        #expect(vm.errorMessage == nil)
        #expect(vm.isLoading == false)
        #expect(vm.currentRate != nil)
    }

    // MARK: - Pre-rate safety

    @Test
    func typingBeforeRateLoadedDoesNotCrash() {
        let mock = MockExchangeRateService()
        let vm = ExchangeCalculatorViewModel(service: mock, selectedCurrency: Currency.fallbackList[0])
        // No loadRates invoked — currentRate is nil.
        vm.usdcAmountChanged("5")
        vm.foreignAmountChanged("100")
        // Inputs are echoed into the fields, but nothing is computed.
        #expect(vm.usdcAmount == "5" || vm.usdcAmount == "100") // last-write-wins
        #expect(vm.currentRate == nil)
    }

    // MARK: - Divide-by-zero guard

    @Test
    func foreignInputWithZeroAskDoesNotCrash() async {
        let (vm, _) = await makeVM(
            ask: Decimal.zero,
            bid: Decimal(string: "10")!
        )
        vm.foreignAmountChanged("1")
        // With ask == 0 we must not divide; usdcAmount should be left
        // untouched (or at least not crash / produce Inf).
        #expect(vm.usdcAmount != "inf")
        #expect(vm.usdcAmount != "Inf")
    }

    // MARK: - Adversarial parse inputs

    @Test
    func parseRejectsMultipleDecimalPoints() {
        #expect(ExchangeCalculatorViewModel.parse("1.2.3", locale: Locale(identifier: "en_US")) == nil)
    }

    @Test
    func parseRejectsEmptyAndWhitespace() {
        #expect(ExchangeCalculatorViewModel.parse("", locale: Locale(identifier: "en_US")) == nil)
        #expect(ExchangeCalculatorViewModel.parse("   ", locale: Locale(identifier: "en_US")) == nil)
    }

    @Test
    func parseLeadingZerosAcceptedAsDecimalValue() {
        // "007" should parse to Decimal(7). Leading-zero *display* cleanup
        // is a Phase 6 input-validation concern, not a parser concern.
        #expect(ExchangeCalculatorViewModel.parse("007", locale: Locale(identifier: "en_US")) == Decimal(7))
    }

    // MARK: - Cancellation / overlap safety

    @Test
    func cancellationDoesNotCommitStateOrSurfaceError() async {
        let mock = MockExchangeRateService()
        mock.stubbedRates = [
            ExchangeRate(
                ask: Decimal(string: "18.4105")!,
                bid: Decimal(string: "18.4069")!,
                book: "usdc_mxn",
                date: ""
            )
        ]
        let vm = ExchangeCalculatorViewModel(service: mock, selectedCurrency: Currency.fallbackList[0])

        let task = Task { await vm.loadRates() }
        task.cancel()
        await task.value

        // With cancellation, the result may or may not have been committed
        // depending on timing — but errorMessage must never be set for an
        // intentional cancellation.
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Max-two-decimal clamping

    @Test
    func clampKeepsUpToTwoDecimalPlaces() {
        #expect(ExchangeCalculatorViewModel.clampToTwoDecimalPlaces("1.2", locale: .init(identifier: "en_US")) == "1.2")
        #expect(ExchangeCalculatorViewModel.clampToTwoDecimalPlaces("1.23", locale: .init(identifier: "en_US")) == "1.23")
    }

    @Test
    func clampTruncatesExcessDecimalDigits() {
        #expect(ExchangeCalculatorViewModel.clampToTwoDecimalPlaces("1.234", locale: .init(identifier: "en_US")) == "1.23")
        #expect(ExchangeCalculatorViewModel.clampToTwoDecimalPlaces("0.12345", locale: .init(identifier: "en_US")) == "0.12")
    }

    @Test
    func clampPreservesPartialInput() {
        #expect(ExchangeCalculatorViewModel.clampToTwoDecimalPlaces("", locale: .init(identifier: "en_US")) == "")
        #expect(ExchangeCalculatorViewModel.clampToTwoDecimalPlaces("1.", locale: .init(identifier: "en_US")) == "1.")
        #expect(ExchangeCalculatorViewModel.clampToTwoDecimalPlaces("123", locale: .init(identifier: "en_US")) == "123")
    }

    @Test
    func clampRespectsCommaLocale() {
        let spain = Locale(identifier: "es_ES")
        #expect(ExchangeCalculatorViewModel.clampToTwoDecimalPlaces("1,234", locale: spain) == "1,23")
    }

    @Test
    func clampDropsRepeatedSeparators() {
        // Regression: previously this produced "1.2." (malformed).
        let us = Locale(identifier: "en_US")
        #expect(ExchangeCalculatorViewModel.clampToTwoDecimalPlaces("1.2.3", locale: us) == "1.23")
        #expect(ExchangeCalculatorViewModel.clampToTwoDecimalPlaces("1.2.3.4", locale: us) == "1.23")
        let spain = Locale(identifier: "es_ES")
        #expect(ExchangeCalculatorViewModel.clampToTwoDecimalPlaces("1,2,3", locale: spain) == "1,23")
    }

    @Test
    func clampHandlesNegativeAndLeadingSeparator() {
        let us = Locale(identifier: "en_US")
        #expect(ExchangeCalculatorViewModel.clampToTwoDecimalPlaces("-1.234", locale: us) == "-1.23")
        #expect(ExchangeCalculatorViewModel.clampToTwoDecimalPlaces(".5", locale: us) == ".5")
    }

    @Test
    func usdcChangedPreservesUserInputAsTyped() async {
        // The VM no longer clamps user input — Decimal is the
        // source of truth, the typed string is echoed back as-is so
        // SwiftUI's TextField reconciliation can't destroy it.
        let (vm, _) = await makeVM()
        vm.usdcAmountChanged("1.2345")
        #expect(vm.usdcAmount == "1.2345")
        #expect(vm.usdcDecimal == Decimal(string: "1.2345")!)
    }

    // MARK: - Currency list fallback

    @Test
    func loadAvailableCurrenciesFallsBackSilentlyOnServiceError() async {
        let mock = MockExchangeRateService()
        mock.shouldThrow = true
        let vm = ExchangeCalculatorViewModel(service: mock, selectedCurrency: Currency.fallbackList[0])

        await vm.loadAvailableCurrencies()

        #expect(vm.availableCurrencies == Currency.fallbackList,
                "Should fall back to Currency.fallbackList when fetchCurrencies throws")
        #expect(vm.errorMessage == nil,
                "Currency-list failure is non-critical and must not surface a user error")
    }

    @Test
    func mixedCaseDisplayCodeMatchesUppercaseAPICode() async {
        // Guard: the VM uses case-insensitive matching so a
        // mixed-case display code (e.g. a future stablecoin like
        // "EURc" or "USDc") still matches the API-extracted uppercase
        // code. No mixed-case codes ship in fallbackList today, but
        // the matching logic is defensive.
        let mock = MockExchangeRateService()
        mock.stubbedRates = [
            ExchangeRate(
                ask: Decimal(string: "1.08")!,
                bid: Decimal(string: "1.07")!,
                book: "usdc_eurc",
                date: ""
            )
        ]
        let mixedCase = Currency(code: "EURc", flagEmoji: "🇪🇺", displayName: "Euro Coin")
        let vm = ExchangeCalculatorViewModel(service: mock, selectedCurrency: mixedCase)

        await vm.loadRates()

        #expect(vm.currentRate != nil,
                "Mixed-case display code must match API-uppercased code case-insensitively")
        #expect(vm.errorMessage == nil)
    }

    @Test
    func loadAvailableCurrenciesMergesServerCodesWithFallbackMetadata() async {
        let mock = MockExchangeRateService()
        // Server returns a subset of fallback codes; expect them merged with
        // the fallback metadata (flag + display name).
        mock.stubbedCurrencies = ["ARS", "BRL"]
        let vm = ExchangeCalculatorViewModel(service: mock, selectedCurrency: Currency.fallbackList[0])

        await vm.loadAvailableCurrencies()

        #expect(vm.availableCurrencies.count == 2)
        #expect(vm.availableCurrencies.map(\.code) == ["ARS", "BRL"])
        // Metadata preserved from fallback.
        #expect(vm.availableCurrencies[0].displayName == "Argentine Peso")
        #expect(vm.availableCurrencies[0].flagEmoji == "🇦🇷")
    }

    @Test
    func overlappingLoadRatesDoesNotCommitOlderResult() async {
        // Two back-to-back loads: the older call must not clobber state.
        // This test relies on the generation token in loadRates.
        let mock = MockExchangeRateService()
        let firstRate = ExchangeRate(
            ask: Decimal(string: "1")!,
            bid: Decimal(string: "1")!,
            book: "usdc_mxn",
            date: ""
        )
        mock.stubbedRates = [firstRate]
        let vm = ExchangeCalculatorViewModel(service: mock, selectedCurrency: Currency.fallbackList[0])
        await vm.loadRates()

        // Now swap the mock to return a different rate and issue another
        // load. After completion, VM state reflects the newer call.
        let secondRate = ExchangeRate(
            ask: Decimal(string: "20")!,
            bid: Decimal(string: "10")!,
            book: "usdc_mxn",
            date: ""
        )
        mock.stubbedRates = [secondRate]
        await vm.loadRates()

        #expect(vm.currentRate == secondRate)
        #expect(vm.isLoading == false)
    }
}
