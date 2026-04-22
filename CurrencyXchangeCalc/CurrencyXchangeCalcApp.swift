import SwiftUI

/// No-op service used when the app is launched by UI tests. Both calls
/// throw, so the VM ends up with no `currentRate` and UI tests get
/// deterministic empty fields instead of fighting live API latency.
private struct NoopUITestService: ExchangeRateServiceProtocol {
    func fetchRates(for currencies: [String]) async throws -> [ExchangeRate] {
        throw CancellationError()
    }
    func fetchCurrencies() async throws -> [String] {
        throw ServiceError.unavailable
    }
}

@main
struct CurrencyXchangeCalcApp: App {
    /// Composition root. Owns the live service and builds the top-level
    /// view model explicitly so tests / previews can substitute their own
    /// service implementations downstream. UI tests pass
    /// `-UITEST_DISABLE_NETWORK` as a launch argument to get a
    /// deterministic no-rate state.
    @State private var viewModel: ExchangeCalculatorViewModel

    init() {
        let service: ExchangeRateServiceProtocol =
            ProcessInfo.processInfo.arguments.contains("-UITEST_DISABLE_NETWORK")
                ? NoopUITestService()
                : LiveExchangeRateService()
        _viewModel = State(wrappedValue: ExchangeCalculatorViewModel(service: service))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
