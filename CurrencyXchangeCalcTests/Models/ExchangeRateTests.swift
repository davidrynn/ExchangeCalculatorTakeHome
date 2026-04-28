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

    /// Regression test with values that specifically survive a Double round-trip badly.
    /// `0.1234567891` and `1.0000000001` both mutate through Double to a
    /// different Decimal. If the decoder ever regresses to String → Double
    /// → Decimal, this test fails loudly.
    @Test
    func decimalsResistDoubleRoundTripCorruption() throws {
        let nastyJSON = """
        [{
          "ask": "0.1234567891",
          "bid": "1.0000000001",
          "book": "usdc_xyz",
          "date": ""
        }]
        """.data(using: .utf8)!

        let rates = try JSONDecoder().decode([ExchangeRate].self, from: nastyJSON)
        #expect(rates[0].ask == Decimal(string: "0.1234567891")!)
        #expect(rates[0].bid == Decimal(string: "1.0000000001")!)

        // Sanity: verify these values ARE mangled by Double — if this ever
        // starts succeeding, Apple's Double precision changed and the test
        // above is no longer a meaningful regression guard.
        let doubleCorrupted = Decimal(Double("0.1234567891")!)
        #expect(doubleCorrupted != Decimal(string: "0.1234567891")!,
                "Precision test is only meaningful while Double mangles this value.")
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

    /// API-shaped timestamp (9 fractional digits, no timezone) parses as
    /// UTC. Pinned to a specific instant so the test is timezone-agnostic.
    @Test
    func publishedAtParsesAPIFormatAsUTC() {
        let rate = ExchangeRate(
            ask: 1, bid: 1, book: "usdc_mxn",
            date: "2025-10-20T20:14:57.361483956"
        )
        let expected = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 2025, month: 10, day: 20,
            hour: 20, minute: 14, second: 57
        ).date
        #expect(rate.publishedAt == expected)
    }

    @Test
    func publishedAtNilForEmptyDate() {
        let rate = ExchangeRate(ask: 1, bid: 1, book: "usdc_mxn", date: "")
        #expect(rate.publishedAt == nil)
    }

    @Test
    func publishedAtNilForMalformedDate() {
        let rate = ExchangeRate(ask: 1, bid: 1, book: "usdc_mxn", date: "not-a-date")
        #expect(rate.publishedAt == nil)
    }

    /// Belt-and-braces: a timestamp with no sub-second part should still
    /// parse. The split-on-`.` step yields the full string when no dot is
    /// present, so the formatter sees a clean `yyyy-MM-dd'T'HH:mm:ss`.
    @Test
    func publishedAtParsesTimestampWithoutFractionalSeconds() {
        let rate = ExchangeRate(
            ask: 1, bid: 1, book: "usdc_mxn",
            date: "2025-10-20T20:14:57"
        )
        let expected = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 2025, month: 10, day: 20,
            hour: 20, minute: 14, second: 57
        ).date
        #expect(rate.publishedAt == expected)
    }

    /// Date-only payloads (e.g. `"2025-10-20"`) are not considered a
    /// publishable timestamp — there's no time component, so we can't
    /// honour the documented UTC instant contract. Returning `nil` keeps
    /// the freshness label hidden rather than rendering a midnight-UTC
    /// guess.
    @Test
    func publishedAtNilForDateOnly() {
        let rate = ExchangeRate(ask: 1, bid: 1, book: "usdc_mxn", date: "2025-10-20")
        #expect(rate.publishedAt == nil)
    }

    /// Locks the current permissive behavior: anything after the first
    /// `.` is treated as the fractional-seconds region and dropped. The
    /// prefix `2025-10-20T20:14:57` still parses, so trailing junk does
    /// not block freshness display. If we ever want strict rejection,
    /// this test will fail and force the conversation.
    @Test
    func publishedAtParsesPrefixWhenTrailingFractionalIsJunk() {
        let rate = ExchangeRate(
            ask: 1, bid: 1, book: "usdc_mxn",
            date: "2025-10-20T20:14:57.bogus"
        )
        let expected = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 2025, month: 10, day: 20,
            hour: 20, minute: 14, second: 57
        ).date
        #expect(rate.publishedAt == expected)
    }
}
