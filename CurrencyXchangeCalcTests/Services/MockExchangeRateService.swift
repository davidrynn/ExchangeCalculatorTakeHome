import Foundation
@testable import CurrencyXchangeCalc

/// Test double for `ExchangeRateServiceProtocol`.
///
/// `@MainActor` because tests drive it sequentially from the main test actor,
/// which sidesteps the need for locking around the mutable stub properties.
/// Conforms to `Sendable` via `@unchecked` since isolation (not locking)
/// provides the safety.
@MainActor
final class MockExchangeRateService: ExchangeRateServiceProtocol, @unchecked Sendable {
    var stubbedRates: [ExchangeRate] = []
    var stubbedCurrencies: [String] = []
    var shouldThrow: Bool = false

    nonisolated func fetchRates(for currencies: [String]) async throws -> [ExchangeRate] {
        try await readState { state in
            if state.shouldThrow { throw ServiceError.unavailable }
            return state.stubbedRates
        }
    }

    nonisolated func fetchCurrencies() async throws -> [String] {
        try await readState { state in
            if state.shouldThrow { throw ServiceError.unavailable }
            return state.stubbedCurrencies
        }
    }

    private nonisolated func readState<T: Sendable>(_ block: @MainActor (MockExchangeRateService) throws -> T) async throws -> T {
        try await MainActor.run { try block(self) }
    }
}
