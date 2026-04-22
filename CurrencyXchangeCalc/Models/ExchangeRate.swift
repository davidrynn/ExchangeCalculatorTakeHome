import Foundation

/// Raw ticker from GET /v1/tickers.
///
/// `Sendable` so decoded values can cross from the nonisolated service into
/// the `@MainActor` view model without boundary warnings.
nonisolated struct ExchangeRate: Codable, Equatable, Sendable {
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
