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
    /// Holds either what the user typed (raw) or a freshly-formatted
    /// computed value. Authoritative numeric value lives in
    /// `usdcDecimal`; never re-clamped or re-parsed from this string.
    var usdcAmount: String = ""

    /// User-visible foreign amount string. See `usdcAmount` notes —
    /// numeric truth is in `foreignDecimal`.
    var foreignAmount: String = ""

    /// Authoritative `Decimal` value behind `usdcAmount`. `nil` when the
    /// field is empty or holds invalid input.
    private(set) var usdcDecimal: Decimal?

    /// Authoritative `Decimal` value behind `foreignAmount`. `nil` when
    /// the field is empty or holds invalid input.
    private(set) var foreignDecimal: Decimal?

    /// Which side the user edited most recently. Used by
    /// `recalculateAfterRateUpdate()` so a fresh rate re-derives the
    /// *other* side from the user's authoritative `Decimal`, not from
    /// a previously-formatted display string. Without this, recomputing
    /// can lose precision (e.g. 0.0576 → clamp → 0.05) and the user
    /// sees values shift after rate refreshes.
    private enum EditedSide: Sendable { case usdc, foreign }
    private var lastEditedSide: EditedSide?

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

    /// User edited the USDc field. Re-derives the foreign side using the
    /// current rate's `bid` (USDc → foreign direction).
    ///
    /// `usdcAmount` echoes the user's raw input as-is — no clamping or
    /// re-formatting — so SwiftUI's TextField reconciliation never
    /// destroys what they typed. Numeric truth is parsed into
    /// `usdcDecimal`; the foreign side is derived from that.
    ///
    /// - Parameter newValue: raw text from the `TextField`.
    func usdcAmountChanged(_ newValue: String) {
        usdcAmount = newValue
        lastEditedSide = .usdc

        if newValue.isEmpty {
            usdcDecimal = nil
            // Only clear the foreign side if it was actually *derived*
            // from this one (i.e. we have a rate). With no rate, the
            // two fields are independent — clearing one shouldn't wipe
            // the other. SwiftUI can fire this setter with an empty
            // string when a TextField loses focus / re-binds, so we
            // need this guard to avoid stomping on independent state.
            if currentRate != nil {
                foreignDecimal = nil
                foreignAmount = ""
            }
            return
        }

        // Invalid input (e.g. "abc", "1.2.3") — leave the typed text on
        // screen but don't touch derived state.
        guard let parsed = Self.parse(newValue) else { return }
        usdcDecimal = parsed
        recomputeForeignFromUsdc()
    }

    /// User edited the foreign field. Re-derives the USDc side using the
    /// current rate's `ask` (foreign → USDc direction).
    ///
    /// - Parameter newValue: raw text from the `TextField`.
    func foreignAmountChanged(_ newValue: String) {
        foreignAmount = newValue
        lastEditedSide = .foreign

        if newValue.isEmpty {
            foreignDecimal = nil
            // See usdcAmountChanged: only cross-clear when the two
            // sides are actually linked by a rate.
            if currentRate != nil {
                usdcDecimal = nil
                usdcAmount = ""
            }
            return
        }

        guard let parsed = Self.parse(newValue) else { return }
        foreignDecimal = parsed
        recomputeUsdcFromForeign()
    }

    // MARK: - Derived recomputation

    private func recomputeForeignFromUsdc() {
        guard let usdc = usdcDecimal, let rate = currentRate else { return }
        let result = usdc * rate.bid
        foreignDecimal = result
        foreignAmount = Self.format(result)
    }

    private func recomputeUsdcFromForeign() {
        guard let foreign = foreignDecimal,
              let rate = currentRate,
              rate.ask != 0 else { return }
        let result = foreign / rate.ask
        usdcDecimal = result
        usdcAmount = Self.format(result)
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
            foreignDecimal = nil
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

    /// After a rate update, re-derive the *non-edited* side from the
    /// `Decimal` source-of-truth held by the side the user last typed
    /// in. This avoids re-parsing display strings (which would round
    /// through the formatter and gradually lose precision on every
    /// rate refresh).
    private func recalculateAfterRateUpdate() {
        switch lastEditedSide {
        case .usdc:
            recomputeForeignFromUsdc()
        case .foreign:
            recomputeUsdcFromForeign()
        case nil:
            // No user input yet — nothing to derive.
            return
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

    /// Formats a `Decimal` for display in the amount fields.
    ///
    /// Always shows **between 4 and 8 fractional digits**. Value-type
    /// formatter, inherently `Sendable` — safe to use from any
    /// isolation, unlike a shared `NumberFormatter`.
    ///
    /// **Why this range — round-trip precision (the edge case):**
    ///
    /// At 2dp, `1 MXN ÷ ask(17.36) ≈ 0.05761` USDc displays as `"0.06"`.
    /// The user re-types `0.06` in USDc and gets `0.06 × bid(17.34) ≈
    /// 1.04 MXN` back, ~4% off from where they started. That looks like
    /// a calculator bug.
    ///
    /// Bumping the minimum to 4 digits keeps `0.0576` USDc visible, and
    /// re-entering it round-trips back to within 0.2% of the original
    /// (the residual loss is the unavoidable bid/ask spread). Matches
    /// how XE, Google's currency widget, and other exchange calculators
    /// format. The `…8` upper bound lets currencies with a wide
    /// USDc-to-foreign ratio (e.g. ARS at ask ≈ 1551 → 0.000645 USDc/peso)
    /// still render meaningful significant digits.
    ///
    /// **Why not the alternative** (track a precise underlying `Decimal`
    /// per field, display only 2dp): introduces parallel state where
    /// the displayed value no longer reflects what the VM actually
    /// holds, and adds complexity for marginal UX gain. The simpler
    /// "show more digits" approach matches industry convention with no
    /// extra state.
    static func format(_ value: Decimal, locale: Locale = .current) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(4...8))
                .locale(locale)
        )
    }
}

private extension Decimal {
    var isFinite: Bool {
        !isNaN && !(self == Decimal.nan)
    }
}
