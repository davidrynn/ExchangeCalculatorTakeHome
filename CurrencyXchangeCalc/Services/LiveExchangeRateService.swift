import Foundation

/// Errors surfaced by `LiveExchangeRateService`.
nonisolated enum ServiceError: Error, LocalizedError, Sendable {
    /// Underlying `URLSession` / transport failure.
    case networkError(String)

    /// Response decoded incorrectly (shape, types, or quoted-decimal parse).
    case decodingError(String)

    /// Endpoint returned 4xx/5xx or is not deployed yet.
    case unavailable

    /// Endpoint returned HTTP status outside the 2xx range.
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "Network error: \(msg)"
        case .decodingError(let msg): return "Decoding error: \(msg)"
        case .unavailable: return "Service unavailable"
        case .httpStatus(let code): return "HTTP \(code)"
        }
    }
}

/// Live implementation backed by `URLSession`.
///
/// Marked `nonisolated` so network I/O runs off the main thread despite the
/// project-wide `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting. Has no
/// mutable state so `Sendable` conformance is implicit (final class + no
/// stored mutable properties).
nonisolated final class LiveExchangeRateService: ExchangeRateServiceProtocol {
    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.dolarapp.dev/v1")!
    ) {
        self.session = session
        self.baseURL = baseURL
        self.decoder = JSONDecoder()
    }

    /// Fetches tickers for the given list of foreign currencies.
    ///
    /// - Parameter currencies: ISO codes (e.g. `["MXN", "ARS"]`). Must be non-empty.
    /// - Returns: Array of `ExchangeRate` — one per currency the server returns.
    /// - Throws: `ServiceError.networkError`, `.httpStatus`, `.decodingError`.
    func fetchRates(for currencies: [String]) async throws -> [ExchangeRate] {
        guard !currencies.isEmpty else { return [] }

        var components = URLComponents(url: baseURL.appendingPathComponent("tickers"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "currencies", value: currencies.joined(separator: ","))]
        guard let url = components.url else {
            throw ServiceError.networkError("Could not build tickers URL")
        }

        let (data, response) = try await performRequest(url: url)
        try validateHTTPResponse(response)

        do {
            return try decoder.decode([ExchangeRate].self, from: data)
        } catch {
            throw ServiceError.decodingError(error.localizedDescription)
        }
    }

    /// Fetches the list of supported foreign currency codes.
    ///
    /// - Returns: ISO codes (e.g. `["MXN", "ARS", "BRL", "COP"]`).
    /// - Throws: `ServiceError.unavailable` when the endpoint is not yet deployed
    ///   (caller should fall back to `Currency.fallbackList`).
    func fetchCurrencies() async throws -> [String] {
        let url = baseURL.appendingPathComponent("tickers-currencies")
        let (data, response) = try await performRequest(url: url)

        if let http = response as? HTTPURLResponse, (400..<600).contains(http.statusCode) {
            throw ServiceError.unavailable
        }

        do {
            return try decoder.decode([String].self, from: data)
        } catch {
            throw ServiceError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func performRequest(url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: url)
        } catch {
            throw ServiceError.networkError(error.localizedDescription)
        }
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw ServiceError.httpStatus(http.statusCode)
        }
    }
}
