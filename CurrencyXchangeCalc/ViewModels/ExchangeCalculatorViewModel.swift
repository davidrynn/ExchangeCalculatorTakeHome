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

    /// `false` (default): USDc row on top, foreign row on bottom.
    /// `true`: foreign row on top, USDc row on bottom. Toggled by
    /// `swapCurrencies()`. Purely a display-position flag — the
    /// amount/currency associations do not change.
    var isSwapped: Bool = false

    /// Monotonically-increasing token bumped on each `loadRates` call.
    /// Guards against an older in-flight fetch clobbering newer state if
    /// overlapping calls ever occur. In the current view layer SwiftUI
    /// `.task(id:)` is the sole cancellation boundary (both currency
    /// changes and Retry go through a composite id), so this is
    /// defense-in-depth for direct callers (tests, future flows).
    private var loadGeneration: UInt64 = 0

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
    /// current rate's `bid` (USDc→foreign direction). Input is clamped
    /// to at most 2 decimal places; extra digits are dropped before
    /// being written back, and SwiftUI reconciles the `TextField` to
    /// the clamped value.
    ///
    /// - Parameter newValue: raw text from the `TextField`.
    func usdcAmountChanged(_ newValue: String) {
        let clamped = Self.clampToTwoDecimalPlaces(newValue)
        usdcAmount = clamped
        guard let rate = currentRate else { return }
        if clamped.isEmpty {
            foreignAmount = ""
            return
        }
        guard let parsed = Self.parse(clamped) else { return }
        let converted = parsed * rate.bid
        foreignAmount = Self.format(converted)
    }

    /// User edited the foreign field. Re-derives `usdcAmount` using the
    /// current rate's `ask` (foreign→USDc direction). Input is clamped
    /// to at most 2 decimal places.
    ///
    /// - Parameter newValue: raw text from the `TextField`.
    func foreignAmountChanged(_ newValue: String) {
        let clamped = Self.clampToTwoDecimalPlaces(newValue)
        foreignAmount = clamped
        guard let rate = currentRate, rate.ask != 0 else { return }
        if clamped.isEmpty {
            usdcAmount = ""
            return
        }
        guard let parsed = Self.parse(clamped) else { return }
        let converted = parsed / rate.ask
        usdcAmount = Self.format(converted)
    }

    // MARK: - Commands

    /// Toggles `isSwapped` so the view flips which row is on top.
    /// Amounts and currency associations stay with their rows — the USDc
    /// amount is still the USDc amount, and the foreign amount is still
    /// the foreign amount. Only their layout position changes.
    func swapCurrencies() {
        isSwapped.toggle()
    }

    /// Sets the selected foreign currency and invalidates any stale rate.
    ///
    /// Does not trigger a network fetch — that is driven by the view's
    /// `.task(id: selectedCurrency.code)` in Phase 5. When the selected
    /// currency changes to a different code, we clear `currentRate` and
    /// `foreignAmount` so the UI cannot render a conversion derived from
    /// the prior currency's rate. The USDc amount stays sticky so the
    /// user's intent is preserved across currency switches.
    ///
    /// - Parameter currency: the newly selected foreign currency.
    func selectCurrency(_ currency: Currency) {
        selectedCurrency = currency
        if let rate = currentRate, rate.currencyCode != currency.code {
            currentRate = nil
            foreignAmount = ""
        }
    }

    /// Fetches the list of supported foreign currencies from the API and
    /// merges it with `Currency.fallbackList`. Falls back silently when
    /// the endpoint isn't deployed (`ServiceError.unavailable`) or the
    /// device has a transport failure (`URLError`). **Decoding errors
    /// and unexpected failures propagate** via `errorMessage` so
    /// programmer bugs are not silently swallowed.
    ///
    /// Intended to be called once when the view appears.
    func loadAvailableCurrencies() async {
        do {
            let codes = try await service.fetchCurrencies()
            if Task.isCancelled { return }
            // Preserve flag + display name from fallback metadata when a
            // server code matches; anything novel is appended with best-
            // effort labels.
            // Case-insensitive lookup so API codes like "EURC" pick up
            // the fallback metadata stored under "EURc".
            let existing = Dictionary(
                uniqueKeysWithValues: Currency.fallbackList.map { ($0.code.uppercased(), $0) }
            )
            let merged: [Currency] = codes.map { code in
                existing[code.uppercased()] ?? Currency(code: code, flagEmoji: "🏳️", displayName: code)
            }
            availableCurrencies = merged.isEmpty ? Currency.fallbackList : merged
        } catch ServiceError.unavailable {
            // Expected — endpoint not deployed yet. Fall back silently.
            availableCurrencies = Currency.fallbackList
        } catch is CancellationError {
            // Structured cancellation — don't touch state.
        } catch let urlError as URLError {
            // Transport failure (offline, DNS, etc). Non-critical for
            // the currency list; fall back silently.
            _ = urlError
            availableCurrencies = Currency.fallbackList
        } catch {
            // Decoding errors and anything else — surface, because these
            // indicate a real bug (schema mismatch, programmer error)
            // rather than a missing endpoint.
            availableCurrencies = Currency.fallbackList
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Fetches the latest rate for `selectedCurrency`. Intended to be
    /// invoked by SwiftUI's `.task(id: selectedCurrency.code)` in Phase 5.
    ///
    /// **Overlap safety:** bumps `loadGeneration` on entry. An older
    /// in-flight call cannot overwrite newer state — rate-commit and
    /// `isLoading` reset both gate on the call's generation matching the
    /// current one. Under `.task(id:)` usage, overlap does not happen in
    /// practice; this is defense-in-depth for direct callers.
    ///
    /// **Cancellation:** checks `Task.isCancelled` after the `await` and
    /// before mutating state. `CancellationError` passes through silently
    /// (no user-visible error) so SwiftUI's task cancellation on id change
    /// is invisible.
    func loadRates() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }

        do {
            let rates = try await service.fetchRates(for: [selectedCurrency.code])
            guard generation == loadGeneration, !Task.isCancelled else { return }
            // Case-insensitive match so mixed-case display codes like
            // "EURc" match API-extracted uppercase codes like "EURC".
            if let rate = rates.first(where: {
                $0.currencyCode.caseInsensitiveCompare(selectedCurrency.code) == .orderedSame
            }) {
                currentRate = rate
                recalculateAfterRateUpdate()
            }
        } catch is CancellationError {
            // Intentional cancellation — no user-facing error.
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
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
    /// Returns `nil` for empty, non-numeric, NaN, malformed input (e.g.
    /// `"1.2.3"`), or scientific notation.
    ///
    /// `Foundation.Decimal(string:)` is permissive — it parses a prefix
    /// and discards the rest, so `"1.2.3"` yields `1.2`. We explicitly
    /// validate the input shape first to reject that.
    static func parse(_ text: String, locale: Locale = .current) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let separator = locale.decimalSeparator ?? "."
        // Accept both the locale separator and ASCII dot so users on
        // comma-locale keyboards can still type with a dot.
        let candidates: [String] = (separator == ".")
            ? [trimmed]
            : [trimmed, trimmed.replacingOccurrences(of: separator, with: ".")]

        for candidate in candidates {
            // Reject anything that isn't digits + exactly-one optional dot,
            // with an optional leading minus. This rejects "1.2.3", "1e5",
            // "1,000.00" (grouping separators), trailing junk, etc.
            if !isWellFormedDecimalString(candidate) { continue }
            if let d = Decimal(string: candidate, locale: Locale(identifier: "en_US_POSIX")) {
                return d.isFinite ? d : nil
            }
        }
        return nil
    }

    /// Clamps user-typed text to at most 2 decimal places. Preserves
    /// partial input like `"1."` or `""` (typing in progress).
    /// Locale-aware: honors the current decimal separator and also
    /// accepts an ASCII dot on comma-locale keyboards.
    ///
    /// If the input contains more than one separator (e.g. `"1.2.3"`)
    /// only the first one is kept; extras are dropped. This makes the
    /// output well-formed even for malformed keystrokes.
    static func clampToTwoDecimalPlaces(_ input: String, locale: Locale = .current) -> String {
        let localeSeparator = locale.decimalSeparator ?? "."
        // Pick whichever separator the user actually typed.
        let effectiveSeparator: String = {
            if localeSeparator != "." && input.contains(localeSeparator) { return localeSeparator }
            if input.contains(".") { return "." }
            return localeSeparator
        }()
        guard let firstRange = input.range(of: effectiveSeparator) else { return input }
        // Integer part is everything before the first separator (preserved as-is).
        let integerPart = String(input[..<firstRange.upperBound])
        // Fractional side: strip any additional separators so "1.2.3" → "23"
        // before truncating to 2 chars.
        let rawFractional = input[firstRange.upperBound...]
        let sanitizedFractional = rawFractional.replacingOccurrences(of: effectiveSeparator, with: "")
        return integerPart + sanitizedFractional.prefix(2)
    }

    /// Matches `[-]? digits [. digits]?` — a plain decimal number with
    /// no grouping, no exponent, no trailing characters.
    private static func isWellFormedDecimalString(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        var scalars = s.unicodeScalars.makeIterator()
        guard var current = scalars.next() else { return false }
        if current == "-" {
            guard let next = scalars.next() else { return false }
            current = next
        }
        var sawDigit = false
        var sawDot = false
        while true {
            if CharacterSet.decimalDigits.contains(current) {
                sawDigit = true
            } else if current == "." {
                if sawDot { return false }
                sawDot = true
            } else {
                return false
            }
            guard let next = scalars.next() else { break }
            current = next
        }
        return sawDigit
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
