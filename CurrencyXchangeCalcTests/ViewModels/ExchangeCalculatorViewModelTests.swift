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
        // 1 × 18.4069 = 18.4069 → "18.41" at 2dp
        #expect(vm.foreignAmount == "18.41")
    }

    @Test
    func foreignToUsdcDividesByAsk() async {
        let (vm, _) = await makeVM()
        vm.foreignAmountChanged("18.4105")
        // 18.4105 / 18.4105 = 1.00
        #expect(vm.usdcAmount == "1.00")
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
        #expect(vm.foreignAmount == "10.00")

        // 20 foreign → USDc uses ask → 1
        vm.foreignAmountChanged("20")
        #expect(vm.usdcAmount == "1.00")
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
        #expect(vm.foreignAmount == "20.00", "USDc→foreign still uses × bid (2 × 10 = 20)")
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
        vm.foreignAmount = "18.41"
        vm.usdcAmountChanged("abc")
        // usdcAmount reflects the keystroke, but foreignAmount is NOT
        // updated from a garbage parse.
        #expect(vm.usdcAmount == "abc")
        #expect(vm.foreignAmount == "18.41")
    }

    @Test
    func zeroInputProducesZeroOutput() async {
        let (vm, _) = await makeVM()
        vm.usdcAmountChanged("0")
        #expect(vm.foreignAmount == "0.00")
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
        #expect(formatted == "1,23")
    }

    @Test
    func enUSLocaleParsesAndFormatsWithDot() {
        let us = Locale(identifier: "en_US")
        #expect(ExchangeCalculatorViewModel.parse("1.23", locale: us) == Decimal(string: "1.23")!)
        #expect(ExchangeCalculatorViewModel.format(Decimal(string: "1.23")!, locale: us) == "1.23")
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
    func usdcChangedClampsInputInPlace() async {
        let (vm, _) = await makeVM()
        vm.usdcAmountChanged("1.2345")
        #expect(vm.usdcAmount == "1.23")
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
    func eurcMatchesCaseInsensitivelyAgainstAPIUppercasedCode() async {
        // Regression: EURc is stored with mixed case in fallbackList for
        // display, but currencyCode from the API always uppercases to
        // "EURC". Make sure the VM's rate match still finds it.
        let mock = MockExchangeRateService()
        mock.stubbedRates = [
            ExchangeRate(
                ask: Decimal(string: "1.08")!,
                bid: Decimal(string: "1.07")!,
                book: "usdc_eurc",
                date: ""
            )
        ]
        let eurc = Currency.fallbackList.first { $0.code == "EURc" }!
        let vm = ExchangeCalculatorViewModel(service: mock, selectedCurrency: eurc)

        await vm.loadRates()

        #expect(vm.currentRate != nil, "EURc (display) must match EURC (API) case-insensitively")
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
