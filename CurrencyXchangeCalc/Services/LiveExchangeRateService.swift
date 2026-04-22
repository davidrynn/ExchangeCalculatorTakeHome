import Foundation

/// Errors surfaced by `LiveExchangeRateService`.
nonisolated enum ServiceError: Error, LocalizedError, Sendable {
    case networkError(String)
    case decodingError(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "Network error: \(msg)"
        case .decodingError(let msg): return "Decoding error: \(msg)"
        case .unavailable: return "Service unavailable"
        }
    }
}

/// Live implementation backed by `URLSession`.
///
/// Marked `nonisolated` so network I/O runs off the main thread despite the
/// project-wide `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting. Has no
/// mutable state so `Sendable` conformance is safe.
nonisolated final class LiveExchangeRateService: ExchangeRateServiceProtocol {
    func fetchRates(for currencies: [String]) async throws -> [ExchangeRate] {
        // TODO: implement in Phase 1
        return []
    }

    func fetchCurrencies() async throws -> [String] {
        // TODO: implement in Phase 1
        throw ServiceError.unavailable
    }
}
