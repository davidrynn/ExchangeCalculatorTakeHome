import Foundation

/// Errors surfaced by `LiveExchangeRateService`.
///
/// `CancellationError` is **not** wrapped — it passes through so that
/// structured-concurrency cancellation (e.g. SwiftUI `.task(id:)`) works
/// without being surfaced as a user-visible error.
nonisolated enum ServiceError: Error, LocalizedError, Sendable {
    /// Underlying `URLSession` / transport failure (timeout, DNS, offline).
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
/// `nonisolated` so network I/O runs off the main thread despite the
/// project-wide `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting. Final
/// class with only `Sendable` stored properties, so the explicit `Sendable`
/// conformance is trivially safe.
nonisolated final class LiveExchangeRateService: ExchangeRateServiceProtocol, Sendable {
    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.dolarapp.dev/v1")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    /// Fetches tickers for the given list of foreign currencies.
    ///
    /// - Parameter currencies: ISO codes (e.g. `["MXN", "ARS"]`). Returns
    ///   an empty array immediately if the list is empty.
    /// - Returns: Array of `ExchangeRate` — one per currency the server returns.
    /// - Throws: `ServiceError` on network/decoding/HTTP failures;
    ///   `CancellationError` passes through unchanged when the caller's
    ///   task is cancelled.
    func fetchRates(for currencies: [String]) async throws -> [ExchangeRate] {
        guard !currencies.isEmpty else { return [] }

        var components = URLComponents(url: baseURL.appendingPathComponent("tickers"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "currencies", value: currencies.joined(separator: ","))]
        guard let url = components.url else {
            throw ServiceError.networkError("Could not build tickers URL")
        }

        let (data, response) = try await performRequest(url: url)
        try validateHTTPResponse(response)
        return try decode([ExchangeRate].self, from: data)
    }

    /// Fetches the list of supported foreign currency codes.
    ///
    /// - Returns: ISO codes (e.g. `["MXN", "ARS", "BRL", "COP"]`).
    /// - Throws: `ServiceError.unavailable` when the endpoint is not yet
    ///   deployed (caller should fall back to `Currency.fallbackList`);
    ///   `CancellationError` passes through unchanged.
    func fetchCurrencies() async throws -> [String] {
        let url = baseURL.appendingPathComponent("tickers-currencies")
        let (data, response) = try await performRequest(url: url)

        if let http = response as? HTTPURLResponse, (400..<600).contains(http.statusCode) {
            throw ServiceError.unavailable
        }

        return try decode([String].self, from: data)
    }

    // MARK: - Private

    private func performRequest(url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: url)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
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

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            // Decoder is local per call — avoids sharing a reference-type
            // decoder across concurrent requests.
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ServiceError.decodingError(error.localizedDescription)
        }
    }
}
