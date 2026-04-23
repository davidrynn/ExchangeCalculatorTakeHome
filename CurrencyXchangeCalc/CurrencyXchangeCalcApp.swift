import SwiftUI

/// No-op service used when `-UITEST_DISABLE_NETWORK` is passed. Both
/// calls throw, so the VM ends up with no `currentRate` and UI tests
/// get deterministic empty fields instead of fighting live API latency.
private struct NoopUITestService: ExchangeRateServiceProtocol {
    func fetchRates(for currencies: [String]) async throws -> [ExchangeRate] {
        throw CancellationError()
    }
    func fetchCurrencies() async throws -> [String] {
        throw ServiceError.unavailable
    }
}

/// UI-test service that returns a fixed MXN rate so input-reflection
/// tests have a predictable multiplier. Active when
/// `-UITEST_SEED_RATE` is passed.
private struct SeededRateUITestService: ExchangeRateServiceProtocol {
    func fetchRates(for currencies: [String]) async throws -> [ExchangeRate] {
        [
            ExchangeRate(
                ask: Decimal(string: "20")!,
                bid: Decimal(string: "10")!,
                book: "usdc_mxn",
                date: ""
            )
        ]
    }
    func fetchCurrencies() async throws -> [String] {
        Currency.fallbackList.map(\.code)
    }
}

/// UI-test service that throws a network error on `fetchRates` so the
/// error banner shows. Active when `-UITEST_FAIL_RATES` is passed.
private struct FailingRatesUITestService: ExchangeRateServiceProtocol {
    func fetchRates(for currencies: [String]) async throws -> [ExchangeRate] {
        throw ServiceError.networkError("Simulated offline")
    }
    func fetchCurrencies() async throws -> [String] {
        throw ServiceError.unavailable
    }
}

@main
struct CurrencyXchangeCalcApp: App {
    /// Composition root. Owns the live service and builds the top-level
    /// view model explicitly so tests / previews can substitute their
    /// own service implementations downstream.
    @State private var viewModel: ExchangeCalculatorViewModel

    init() {
        let args = ProcessInfo.processInfo.arguments
        let service: ExchangeRateServiceProtocol
        if args.contains("-UITEST_FAIL_RATES") {
            service = FailingRatesUITestService()
        } else if args.contains("-UITEST_SEED_RATE") {
            service = SeededRateUITestService()
        } else if args.contains("-UITEST_DISABLE_NETWORK") {
            service = NoopUITestService()
        } else {
            service = LiveExchangeRateService()
        }
        _viewModel = State(wrappedValue: ExchangeCalculatorViewModel(service: service))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
