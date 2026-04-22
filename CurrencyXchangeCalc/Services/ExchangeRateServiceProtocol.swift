import Foundation

/// Abstracts exchange rate network calls; conforming types can be swapped for mocks in tests.
///
/// Conformers are `Sendable` so they may be held by the `@MainActor` view model
/// while running their work off the main thread. Methods are explicitly
/// `nonisolated` so that a conformer cannot accidentally inherit the module's
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` default and pin network I/O to
/// the main thread.
protocol ExchangeRateServiceProtocol: Sendable {
    /// Fetches current tickers for the given currency codes.
    nonisolated func fetchRates(for currencies: [String]) async throws -> [ExchangeRate]

    /// Fetches available currency codes; throws if the API is unavailable.
    nonisolated func fetchCurrencies() async throws -> [String]
}
