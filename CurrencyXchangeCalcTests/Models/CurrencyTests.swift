import Testing
@testable import CurrencyXchangeCalc

struct CurrencyTests {
    @Test
    func fallbackListHasExpectedCurrencies() {
        // Mirrors the spec's example response for /v1/tickers-currencies.
        // Locked in per the recruiter's guidance (2026-04-24).
        #expect(Currency.fallbackList.count == 4)
        let codes = Currency.fallbackList.map(\.code)
        #expect(codes == ["MXN", "ARS", "BRL", "COP"])
    }

    @Test
    func everyFallbackCurrencyHasContent() {
        for currency in Currency.fallbackList {
            #expect(!currency.code.isEmpty, "\(currency) missing code")
            #expect(!currency.flagEmoji.isEmpty, "\(currency.code) missing flag")
            #expect(!currency.displayName.isEmpty, "\(currency.code) missing displayName")
        }
    }

    @Test
    func identifiableByCode() {
        let mxn = Currency(code: "MXN", flagEmoji: "🇲🇽", displayName: "Mexican Peso")
        #expect(mxn.id == "MXN")
    }
}
