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
    /// Mirrors the spec's example response (`/v1/tickers-currencies`
    /// returning `["MXN","ARS","BRL","COP"]`). The recruiter confirmed
    /// the endpoint is intentionally missing for this exercise and the
    /// fallback should stand in for it until the endpoint ships.
    ///
    /// Matching against API responses is case-insensitive in the VM,
    /// so stablecoin-style mixed-case codes (e.g. `EURc`) would work if
    /// they appeared — none in this list today.
    static let fallbackList: [Currency] = [
        Currency(code: "MXN", flagEmoji: "🇲🇽", displayName: "Mexican Peso"),
        Currency(code: "ARS", flagEmoji: "🇦🇷", displayName: "Argentine Peso"),
        Currency(code: "BRL", flagEmoji: "🇧🇷", displayName: "Brazilian Real"),
        Currency(code: "COP", flagEmoji: "🇨🇴", displayName: "Colombian Peso"),
    ]
}
