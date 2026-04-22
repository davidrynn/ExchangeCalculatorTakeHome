import Foundation

/// Abstracts exchange rate network calls; conforming types can be swapped for mocks in tests.
///
/// Conformers are `Sendable` so they may be held by the `@MainActor` view model
/// while running their work off the main thread.
protocol ExchangeRateServiceProtocol: Sendable {
    /// Fetches current tickers for the given currency codes.
    func fetchRates(for currencies: [String]) async throws -> [ExchangeRate]

    /// Fetches available currency codes; throws if the API is unavailable.
    func fetchCurrencies() async throws -> [String]
}
