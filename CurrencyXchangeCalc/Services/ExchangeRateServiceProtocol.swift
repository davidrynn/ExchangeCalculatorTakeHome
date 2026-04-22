import Foundation

/// Abstracts exchange rate network calls; conforming types can be swapped for mocks in tests.
protocol ExchangeRateServiceProtocol {
    /// Fetches current tickers for the given currency codes.
    func fetchRates(for currencies: [String]) async throws -> [ExchangeRate]

    /// Fetches available currency codes; throws if the API is unavailable.
    func fetchCurrencies() async throws -> [String]
}
