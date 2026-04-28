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

/// UI-test service returning a fixed MXN rate (bid=10, ask=20) with a
/// real API-shaped timestamp so input-reflection tests get predictable
/// math AND the freshness label / refresh button render. Active when
/// `-UITEST_SEED_RATE` is passed.
private struct SeededRateUITestService: ExchangeRateServiceProtocol {
    func fetchRates(for currencies: [String]) async throws -> [ExchangeRate] {
        [
            ExchangeRate(
                ask: Decimal(string: "20")!,
                bid: Decimal(string: "10")!,
                book: "usdc_mxn",
                date: "2025-10-20T20:14:57.361483956"
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

/// Actor wrapper so the service below can stay `Sendable` while
/// mutating call-count state.
private actor RateCallCounter {
    private var count: Int = 0
    func next() -> Int {
        count += 1
        return count
    }
}

/// UI-test service returning a *different* rate on each call (bid/ask
/// bumped per call number) so a test can prove the refresh button
/// actually re-ran the load — the visible rate label changes between
/// calls. Active when `-UITEST_INCREMENT_RATE` is passed.
private final class IncrementingRateUITestService: ExchangeRateServiceProtocol {
    private let counter = RateCallCounter()
    func fetchRates(for currencies: [String]) async throws -> [ExchangeRate] {
        let n = await counter.next()
        return [
            ExchangeRate(
                ask: Decimal(20 + n),
                bid: Decimal(10 + n),
                book: "usdc_mxn",
                date: "2025-10-20T20:14:57.361483956"
            )
        ]
    }
    func fetchCurrencies() async throws -> [String] {
        Currency.fallbackList.map(\.code)
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
        } else if args.contains("-UITEST_INCREMENT_RATE") {
            service = IncrementingRateUITestService()
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
