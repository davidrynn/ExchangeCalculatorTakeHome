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
    func swapExchangesAmounts() async {
        let (vm, _) = await makeVM()
        vm.usdcAmount = "1.00"
        vm.foreignAmount = "18.41"
        vm.swapCurrencies()
        #expect(vm.usdcAmount == "18.41")
        #expect(vm.foreignAmount == "1.00")
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
        let (vm, _) = await makeVM(currency: Currency.fallbackList[0]) // MXN
        #expect(vm.currentRate != nil)
        vm.selectCurrency(Currency.fallbackList[1]) // ARS
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
}
