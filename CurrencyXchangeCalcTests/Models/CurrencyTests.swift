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

    /// Locks the `.narrow` presentation contract: pesos render as "$"
    /// (not "MX$"), Brazilian reals as "R$". If Apple ever changes the
    /// CLDR data underlying these forms this test will fire and force a
    /// conversation about whether to follow the change.
    @Test
    func symbolUsesNarrowLocalForm() {
        let mxn = Currency(code: "MXN", flagEmoji: "🇲🇽", displayName: "Mexican Peso")
        let brl = Currency(code: "BRL", flagEmoji: "🇧🇷", displayName: "Brazilian Real")
        #expect(mxn.symbol == "$", "Got \(mxn.symbol)")
        #expect(brl.symbol == "R$", "Got \(brl.symbol)")
    }

    /// USD-pegged stablecoins (USDc, USDC, USDt, etc.) inherit the
    /// dollar sign — they trade 1:1 with USD by design, and rendering
    /// the raw code "USDc" next to the value reads as a typo.
    @Test
    func symbolForUSDStablecoinIsDollar() {
        let usdc = Currency(code: "USDc", flagEmoji: "🇺🇸", displayName: "USD Coin")
        let usdt = Currency(code: "USDt", flagEmoji: "🇺🇸", displayName: "Tether")
        #expect(usdc.symbol == "$", "Got \(usdc.symbol)")
        #expect(usdt.symbol == "$", "Got \(usdt.symbol)")
    }

    /// Truly unknown codes (not USD-prefixed) still fall back to the
    /// code itself — better to show the literal code than guess a
    /// symbol that could mislead.
    @Test
    func symbolFallsBackToCodeForUnknownCurrency() {
        let xyz = Currency(code: "XYZ", flagEmoji: "🏳️", displayName: "Mystery")
        #expect(xyz.symbol == "XYZ", "Got \(xyz.symbol)")
    }
}
