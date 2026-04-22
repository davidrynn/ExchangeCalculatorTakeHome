import Foundation

/// A supported currency for exchange against USDc.
///
/// Value type; `Sendable` so it can cross actor boundaries between the
/// nonisolated service layer and the `@MainActor` view model.
nonisolated struct Currency: Identifiable, Hashable, Sendable {
    let code: String
    let flagEmoji: String
    let displayName: String

    var id: String { code }

    /// Hardcoded fallback list used when the currencies API is unavailable.
    static let fallbackList: [Currency] = []  // TODO: populate in Phase 1
}
