import Foundation

/// A supported currency for exchange against USDc.
///
/// Value type; `Sendable` so it can cross actor boundaries between the
/// nonisolated service layer and the `@MainActor` view model.
nonisolated struct Currency: Identifiable, Hashable, Sendable {
    /// ISO 4217 currency code (e.g. `"MXN"`).
    let code: String

    /// Unicode flag emoji for the country (e.g. `"🇲🇽"`).
    let flagEmoji: String

    /// Human-readable currency name (e.g. `"Mexican Peso"`).
    let displayName: String

    var id: String { code }

    /// Hardcoded fallback used when the `tickers-currencies` API is unavailable.
    ///
    /// Must match the set of currencies supported by the `tickers` endpoint.
    static let fallbackList: [Currency] = [
        Currency(code: "MXN", flagEmoji: "🇲🇽", displayName: "Mexican Peso"),
        Currency(code: "ARS", flagEmoji: "🇦🇷", displayName: "Argentine Peso"),
        Currency(code: "BRL", flagEmoji: "🇧🇷", displayName: "Brazilian Real"),
        Currency(code: "COP", flagEmoji: "🇨🇴", displayName: "Colombian Peso"),
    ]
}
