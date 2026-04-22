import Foundation
import Observation

/// Manages all state and business logic for the exchange calculator screen.
@Observable
final class ExchangeCalculatorViewModel {
    var usdcAmount: String = ""
    var foreignAmount: String = ""
    var selectedCurrency: Currency = Currency.fallbackList.first ?? Currency(code: "MXN", flagEmoji: "🇲🇽", displayName: "Mexican Peso")
    var availableCurrencies: [Currency] = Currency.fallbackList
    var isLoading: Bool = false
    var errorMessage: String?

    private let service: ExchangeRateServiceProtocol
    private var currentRate: ExchangeRate?

    init(service: ExchangeRateServiceProtocol = LiveExchangeRateService()) {
        self.service = service
    }

    /// Called when the user edits the USDc field; recalculates foreignAmount.
    func usdcAmountChanged(_ newValue: String) {
        // TODO: implement in Phase 2
    }

    /// Called when the user edits the foreign field; recalculates usdcAmount.
    func foreignAmountChanged(_ newValue: String) {
        // TODO: implement in Phase 2
    }

    /// Swaps USDc ↔ selected currency positions (swaps displayed amounts).
    func swapCurrencies() {
        // TODO: implement in Phase 2
        let temp = usdcAmount
        usdcAmount = foreignAmount
        foreignAmount = temp
    }

    /// Sets selectedCurrency and re-fetches rates.
    func selectCurrency(_ currency: Currency) {
        // TODO: implement in Phase 2
        selectedCurrency = currency
    }

    /// Initiates API fetch; falls back to hardcoded currencies on error.
    func loadRates() async {
        // TODO: implement in Phase 2
    }
}
