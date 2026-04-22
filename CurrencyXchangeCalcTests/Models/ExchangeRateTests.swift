import Foundation
import Testing
@testable import CurrencyXchangeCalc

struct ExchangeRateTests {
    private static let sampleJSON = """
    [
      {
        "ask": "18.4105000000",
        "bid": "18.4069700000",
        "book": "usdc_mxn",
        "date": "2025-10-20T20:14:57.361483956"
      },
      {
        "ask": "1551.0000000000",
        "bid": "1539.4290300000",
        "book": "usdc_ars",
        "date": "2025-10-21T09:44:18.512194175"
      }
    ]
    """.data(using: .utf8)!

    @Test
    func decodesSampleResponse() throws {
        let rates = try JSONDecoder().decode([ExchangeRate].self, from: Self.sampleJSON)
        #expect(rates.count == 2)
        #expect(rates[0].book == "usdc_mxn")
        #expect(rates[1].book == "usdc_ars")
    }

    @Test
    func quotedDecimalsDecodeWithFullPrecision() throws {
        let rates = try JSONDecoder().decode([ExchangeRate].self, from: Self.sampleJSON)
        // Exact string match — guards against Double round-trip precision loss.
        #expect(rates[0].ask == Decimal(string: "18.4105000000")!)
        #expect(rates[0].bid == Decimal(string: "18.4069700000")!)
        #expect(rates[1].ask == Decimal(string: "1551.0000000000")!)
        #expect(rates[1].bid == Decimal(string: "1539.4290300000")!)
    }

    @Test
    func currencyCodeExtractedFromBook() {
        let rate = ExchangeRate(ask: 1, bid: 1, book: "usdc_mxn", date: "")
        #expect(rate.currencyCode == "MXN")
    }

    @Test
    func currencyCodeHandlesUppercaseBook() {
        let rate = ExchangeRate(ask: 1, bid: 1, book: "USDC_BRL", date: "")
        #expect(rate.currencyCode == "BRL")
    }

    @Test
    func currencyCodeEmptyForMalformedBook() {
        let rate = ExchangeRate(ask: 1, bid: 1, book: "garbage", date: "")
        #expect(rate.currencyCode == "")
    }

    @Test
    func malformedJSONThrowsDecodingError() {
        let badJSON = """
        [{"ask":"not-a-number","bid":"1","book":"usdc_mxn","date":""}]
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([ExchangeRate].self, from: badJSON)
        }
    }

    @Test
    func missingKeyThrowsDecodingError() {
        let badJSON = """
        [{"ask":"1","book":"usdc_mxn","date":""}]
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([ExchangeRate].self, from: badJSON)
        }
    }
}
