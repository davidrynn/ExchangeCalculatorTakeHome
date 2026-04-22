import Foundation
import Testing
@testable import CurrencyXchangeCalc

struct LiveExchangeRateServiceTests {

    /// Concurrency smoke test: verifies `fetchRates` is callable from a
    /// non-isolated context (the test function has no isolation) without
    /// MainActor inference. Compile-time assertion — no network required.
    @Test
    func fetchRatesIsCallableFromNonisolatedContext() async {
        let service = LiveExchangeRateService(baseURL: URL(string: "http://127.0.0.1:1/")!)
        // We expect a network error here; the important part is that the call
        // compiles without MainActor hop warnings.
        do {
            _ = try await service.fetchRates(for: ["MXN"])
            Issue.record("Expected network failure against invalid URL")
        } catch is ServiceError {
            // expected
        } catch {
            Issue.record("Expected ServiceError, got \(type(of: error))")
        }
    }

    @Test
    func fetchRatesReturnsEmptyForEmptyInput() async throws {
        let service = LiveExchangeRateService()
        let rates = try await service.fetchRates(for: [])
        #expect(rates.isEmpty)
    }
}
