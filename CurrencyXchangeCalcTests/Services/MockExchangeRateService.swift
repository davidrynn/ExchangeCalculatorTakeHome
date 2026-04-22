import Foundation
@testable import CurrencyXchangeCalc

/// Test double for ExchangeRateServiceProtocol.
final class MockExchangeRateService: ExchangeRateServiceProtocol {
    var stubbedRates: [ExchangeRate] = []
    var stubbedCurrencies: [String] = []
    var shouldThrow: Bool = false

    func fetchRates(for currencies: [String]) async throws -> [ExchangeRate] {
        if shouldThrow { throw ServiceError.unavailable }
        return stubbedRates
    }

    func fetchCurrencies() async throws -> [String] {
        if shouldThrow { throw ServiceError.unavailable }
        return stubbedCurrencies
    }
}
