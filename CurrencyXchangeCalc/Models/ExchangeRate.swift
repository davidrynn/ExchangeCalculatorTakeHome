import Foundation

/// Raw ticker from GET /v1/tickers.
struct ExchangeRate: Codable, Equatable {
    let ask: Decimal
    let bid: Decimal
    let book: String
    let date: String

    /// Extracts the foreign currency code from book (e.g. "usdc_mxn" → "MXN").
    var currencyCode: String {
        // TODO: implement in Phase 1
        return ""
    }
}
