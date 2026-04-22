import Foundation

/// A supported currency for exchange against USDc.
struct Currency: Identifiable, Hashable {
    let code: String
    let flagEmoji: String
    let displayName: String

    var id: String { code }

    /// Hardcoded fallback list used when the currencies API is unavailable.
    static let fallbackList: [Currency] = []  // TODO: populate in Phase 1
}
