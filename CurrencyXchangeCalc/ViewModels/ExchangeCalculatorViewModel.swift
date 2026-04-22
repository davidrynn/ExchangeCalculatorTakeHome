import Foundation
import Observation

/// Manages state and business logic for the exchange calculator screen.
///
/// Explicitly `@MainActor` (also the project default) since all state is
/// observed by SwiftUI. The injected service is `Sendable` + `nonisolated`,
/// so `await service.fetchRates(...)` hops off the main thread for the I/O
/// and back on to mutate state.
///
/// **Bid/ask convention (single source of truth in `Docs/ImplementationPlan.md`):**
/// - USDc → foreign: `× bid`
/// - Foreign → USDc: `÷ ask`
///
/// Phase 2 is exercised only via `MockExchangeRateService`; live URLSession
/// wiring moves in Phase 5 (no VM changes required — just injection).
@MainActor
@Observable
final class ExchangeCalculatorViewModel {

    // MARK: - Observed state

    /// User-visible USDc amount string (what the USDc `TextField` binds to).
    var usdcAmount: String = ""

    /// User-visible foreign amount string.
    var foreignAmount: String = ""

    /// Currently selected foreign currency.
    var selectedCurrency: Currency

    /// Currencies available in the picker.
    var availableCurrencies: [Currency]

    /// True while an async `loadRates` is in flight.
    var isLoading: Bool = false

    /// User-surfaceable error message (banner text). `nil` when healthy.
    var errorMessage: String?

    // MARK: - Dependencies

    private let service: ExchangeRateServiceProtocol

    /// Most recent rate for `selectedCurrency`. `nil` until the first
    /// successful `loadRates`.
    private(set) var currentRate: ExchangeRate?

    // MARK: - Init

    init(
        service: ExchangeRateServiceProtocol = LiveExchangeRateService(),
        selectedCurrency: Currency = Currency.fallbackList.first
            ?? Currency(code: "MXN", flagEmoji: "🇲🇽", displayName: "Mexican Peso"),
        availableCurrencies: [Currency] = Currency.fallbackList
    ) {
        self.service = service
        self.selectedCurrency = selectedCurrency
        self.availableCurrencies = availableCurrencies
    }

    // MARK: - Input handlers

    /// User edited the USDc field. Re-derives `foreignAmount` using the
    /// current rate's `bid` (USDc→foreign direction).
    ///
    /// - Parameter newValue: raw text from the `TextField`.
    func usdcAmountChanged(_ newValue: String) {
        usdcAmount = newValue
        guard let rate = currentRate else { return }
        if newValue.isEmpty {
            foreignAmount = ""
            return
        }
        guard let parsed = Self.parse(newValue) else { return }
        let converted = parsed * rate.bid
        foreignAmount = Self.format(converted)
    }

    /// User edited the foreign field. Re-derives `usdcAmount` using the
    /// current rate's `ask` (foreign→USDc direction).
    ///
    /// - Parameter newValue: raw text from the `TextField`.
    func foreignAmountChanged(_ newValue: String) {
        foreignAmount = newValue
        guard let rate = currentRate, rate.ask != 0 else { return }
        if newValue.isEmpty {
            usdcAmount = ""
            return
        }
        guard let parsed = Self.parse(newValue) else { return }
        let converted = parsed / rate.ask
        usdcAmount = Self.format(converted)
    }

    // MARK: - Commands

    /// Swaps the two displayed amounts. The currency assignment itself
    /// stays the same (USDc is always USDc); the swap reflects the
    /// user's intent to flip which side they're thinking about.
    func swapCurrencies() {
        let temp = usdcAmount
        usdcAmount = foreignAmount
        foreignAmount = temp
    }

    /// Sets the selected foreign currency and re-derives the foreign amount
    /// in-memory using the current USDc value. Does not trigger a network
    /// fetch — that is driven by the view's `.task(id:)` in Phase 5.
    ///
    /// - Parameter currency: the newly selected foreign currency.
    func selectCurrency(_ currency: Currency) {
        selectedCurrency = currency
        // Invalidate stale rate if it's for a different book.
        if let rate = currentRate, rate.currencyCode != currency.code {
            currentRate = nil
            foreignAmount = ""
        }
    }

    /// Fetches the latest rate for `selectedCurrency`. Intended to be
    /// invoked by SwiftUI's `.task(id: selectedCurrency.code)` in Phase 5.
    ///
    /// Honors cooperative cancellation — checks `Task.isCancelled` after
    /// the `await` and before mutating state, so a stale response never
    /// overwrites newer state. Cancellation is never surfaced as an error.
    func loadRates() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let rates = try await service.fetchRates(for: [selectedCurrency.code])
            if Task.isCancelled { return }
            if let rate = rates.first(where: { $0.currencyCode == selectedCurrency.code }) {
                currentRate = rate
                recalculateAfterRateUpdate()
            }
        } catch is CancellationError {
            // Intentional cancellation — no user-facing error.
        } catch {
            if Task.isCancelled { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Private

    private func recalculateAfterRateUpdate() {
        // After a rate refresh, re-derive the foreign side from the USDc
        // side if present; otherwise clear both. This keeps the USDc side
        // sticky across currency changes.
        if usdcAmount.isEmpty {
            foreignAmount = ""
        } else {
            usdcAmountChanged(usdcAmount)
        }
    }

    /// Parses user text into a `Decimal`, respecting `Locale.current` so
    /// comma-decimal locales (e.g. `es_ES`) work without translation.
    /// Returns `nil` for empty, non-numeric, NaN, or otherwise unparseable input.
    static func parse(_ text: String, locale: Locale = .current) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Accept both locale decimal and ASCII dot so we don't have to
        // know the user's keyboard layout.
        let candidates: [String] = {
            let separator = locale.decimalSeparator ?? "."
            if separator == "." {
                return [trimmed]
            }
            return [trimmed, trimmed.replacingOccurrences(of: separator, with: ".")]
        }()
        for candidate in candidates {
            if let d = Decimal(string: candidate, locale: locale) {
                return d.isFinite ? d : nil
            }
            if let d = Decimal(string: candidate, locale: Locale(identifier: "en_US_POSIX")) {
                return d.isFinite ? d : nil
            }
        }
        return nil
    }

    /// Formats a `Decimal` to 2 fractional digits using `Decimal.FormatStyle`.
    /// Value-type formatter, inherently `Sendable` — safe to use from any
    /// isolation, unlike a shared `NumberFormatter`.
    static func format(_ value: Decimal, locale: Locale = .current) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(2))
                .locale(locale)
        )
    }
}

private extension Decimal {
    var isFinite: Bool {
        !isNaN && !(self == Decimal.nan)
    }
}
