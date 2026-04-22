import Foundation
import Testing
@testable import CurrencyXchangeCalc

/// `URLProtocol` stub that intercepts requests and replays a canned
/// (status, body) tuple registered under the request's URL. Thread-safe
/// via an internal lock so a serialized test suite can share it safely.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var _stubs: [String: (Int, Data)] = [:]
    private static var _capturedURLs: [URL] = []

    static func setStub(for urlString: String, status: Int, body: Data) {
        lock.lock(); defer { lock.unlock() }
        _stubs[urlString] = (status, body)
    }

    static func takeCapturedURLs() -> [URL] {
        lock.lock(); defer { lock.unlock() }
        let urls = _capturedURLs
        return urls
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _stubs = [:]
        _capturedURLs = []
    }

    private static func stub(for url: URL) -> (Int, Data)? {
        lock.lock(); defer { lock.unlock() }
        _capturedURLs.append(url)
        return _stubs[url.absoluteString]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        guard let (status, data) = Self.stub(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeMockedSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

/// Serialized suite so that `MockURLProtocol`'s shared stub state is not
/// mutated by parallel tests. Unit tests that don't touch the mock live
/// in `ExchangeRateTests` / `CurrencyTests` and stay parallel.
@Suite(.serialized)
struct LiveExchangeRateServiceTests {

    // MARK: - fetchRates

    @Test
    func fetchRatesReturnsEmptyForEmptyInput() async throws {
        MockURLProtocol.reset()
        let service = LiveExchangeRateService(session: makeMockedSession(), baseURL: URL(string: "https://api.test/v1")!)
        let rates = try await service.fetchRates(for: [])
        #expect(rates.isEmpty)
        #expect(MockURLProtocol.takeCapturedURLs().isEmpty, "No request should fire for empty input")
    }

    @Test
    func fetchRatesBuildsCommaSeparatedURL() async throws {
        MockURLProtocol.reset()
        let base = URL(string: "https://api.test/v1")!
        let expectedURL = "https://api.test/v1/tickers?currencies=MXN,ARS"
        MockURLProtocol.setStub(for: expectedURL, status: 200, body: "[]".data(using: .utf8)!)

        let service = LiveExchangeRateService(session: makeMockedSession(), baseURL: base)
        _ = try await service.fetchRates(for: ["MXN", "ARS"])

        let captured = MockURLProtocol.takeCapturedURLs()
        #expect(captured.count == 1)
        #expect(captured.first?.absoluteString == expectedURL)
    }

    @Test
    func fetchRatesDecodesSuccessResponse() async throws {
        MockURLProtocol.reset()
        let base = URL(string: "https://api.test/v1")!
        let expectedURL = "https://api.test/v1/tickers?currencies=MXN"
        let body = """
        [{"ask":"18.4105","bid":"18.4069","book":"usdc_mxn","date":"2025-10-20"}]
        """.data(using: .utf8)!
        MockURLProtocol.setStub(for: expectedURL, status: 200, body: body)

        let service = LiveExchangeRateService(session: makeMockedSession(), baseURL: base)
        let rates = try await service.fetchRates(for: ["MXN"])

        #expect(rates.count == 1)
        #expect(rates[0].currencyCode == "MXN")
        #expect(rates[0].ask == Decimal(string: "18.4105")!)
    }

    @Test
    func fetchRatesThrowsHTTPStatusOn500() async {
        MockURLProtocol.reset()
        let base = URL(string: "https://api.test/v1")!
        let expectedURL = "https://api.test/v1/tickers?currencies=MXN"
        MockURLProtocol.setStub(for: expectedURL, status: 500, body: Data())

        let service = LiveExchangeRateService(session: makeMockedSession(), baseURL: base)
        do {
            _ = try await service.fetchRates(for: ["MXN"])
            Issue.record("Expected HTTP 500 error")
        } catch ServiceError.httpStatus(let code) {
            #expect(code == 500)
        } catch {
            Issue.record("Expected ServiceError.httpStatus, got \(error)")
        }
    }

    @Test
    func fetchRatesThrowsDecodingErrorOnGarbageBody() async {
        MockURLProtocol.reset()
        let base = URL(string: "https://api.test/v1")!
        let expectedURL = "https://api.test/v1/tickers?currencies=MXN"
        MockURLProtocol.setStub(for: expectedURL, status: 200, body: "not-json".data(using: .utf8)!)

        let service = LiveExchangeRateService(session: makeMockedSession(), baseURL: base)
        do {
            _ = try await service.fetchRates(for: ["MXN"])
            Issue.record("Expected decoding error")
        } catch ServiceError.decodingError {
            // expected
        } catch {
            Issue.record("Expected ServiceError.decodingError, got \(error)")
        }
    }

    // MARK: - fetchCurrencies

    @Test
    func fetchCurrenciesSuccess() async throws {
        MockURLProtocol.reset()
        let base = URL(string: "https://api.test/v1")!
        let expectedURL = "https://api.test/v1/tickers-currencies"
        MockURLProtocol.setStub(for: expectedURL, status: 200, body: #"["MXN","ARS","BRL","COP"]"#.data(using: .utf8)!)

        let service = LiveExchangeRateService(session: makeMockedSession(), baseURL: base)
        let codes = try await service.fetchCurrencies()
        #expect(codes == ["MXN", "ARS", "BRL", "COP"])
    }

    @Test
    func fetchCurrenciesMaps404ToUnavailable() async {
        MockURLProtocol.reset()
        let base = URL(string: "https://api.test/v1")!
        MockURLProtocol.setStub(for: "https://api.test/v1/tickers-currencies", status: 404, body: Data())

        let service = LiveExchangeRateService(session: makeMockedSession(), baseURL: base)
        do {
            _ = try await service.fetchCurrencies()
            Issue.record("Expected unavailable error")
        } catch ServiceError.unavailable {
            // expected — callers fall back to Currency.fallbackList
        } catch {
            Issue.record("Expected ServiceError.unavailable, got \(error)")
        }
    }

    @Test
    func fetchCurrenciesMaps500ToUnavailable() async {
        MockURLProtocol.reset()
        let base = URL(string: "https://api.test/v1")!
        MockURLProtocol.setStub(for: "https://api.test/v1/tickers-currencies", status: 500, body: Data())

        let service = LiveExchangeRateService(session: makeMockedSession(), baseURL: base)
        do {
            _ = try await service.fetchCurrencies()
            Issue.record("Expected unavailable error")
        } catch ServiceError.unavailable {
            // expected
        } catch {
            Issue.record("Expected ServiceError.unavailable, got \(error)")
        }
    }

    // MARK: - Concurrency

    @Test
    func serviceIsCallableFromNonisolatedContext() async {
        // Uses a real URLSession against an unreachable port so we only
        // verify the call site compiles from a nonisolated context.
        let service = LiveExchangeRateService(baseURL: URL(string: "http://127.0.0.1:1/")!)
        do {
            _ = try await service.fetchRates(for: ["MXN"])
            Issue.record("Expected network failure against invalid URL")
        } catch is ServiceError {
            // expected
        } catch {
            Issue.record("Expected ServiceError, got \(type(of: error))")
        }
    }
}
