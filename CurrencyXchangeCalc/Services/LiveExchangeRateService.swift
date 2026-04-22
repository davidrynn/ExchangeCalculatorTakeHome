import Foundation

enum ServiceError: Error, LocalizedError {
    case networkError(Error)
    case decodingError(Error)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .decodingError(let e): return "Decoding error: \(e.localizedDescription)"
        case .unavailable: return "Service unavailable"
        }
    }
}

/// Live implementation using URLSession.
final class LiveExchangeRateService: ExchangeRateServiceProtocol {
    func fetchRates(for currencies: [String]) async throws -> [ExchangeRate] {
        // TODO: implement in Phase 1
        return []
    }

    func fetchCurrencies() async throws -> [String] {
        // TODO: implement in Phase 1
        throw ServiceError.unavailable
    }
}
