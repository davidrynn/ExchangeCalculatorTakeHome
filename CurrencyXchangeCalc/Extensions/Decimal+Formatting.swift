import Foundation

/// App-specific display formatting for `Decimal` values. Two precisions
/// because the calculator surfaces decimals in two different contexts —
/// each has its own rule, documented in `README.md` (*Display precision*).
extension Decimal {

    /// Formats as a user-facing amount-field value (USDc / foreign input).
    ///
    /// **4–8 fractional digits.** The minimum of 4 prevents the round-trip
    /// drift bug (typing `1 MXN`, seeing `0.06 USDc`, retyping that, getting
    /// `1.04 MXN` back); the maximum of 8 keeps wide-ratio currencies like
    /// ARS (ask ≈ 1551 → 0.000645 USDc/peso) showing meaningful significant
    /// digits. See README's *Display precision* section for the full story.
    ///
    /// Used by the VM to produce the strings stored in `usdcAmount` /
    /// `foreignAmount` (the source of truth the `TextField`s bind to).
    func formattedAsAmount(locale: Locale = .current) -> String {
        formatted(.number.precision(.fractionLength(4...8)).locale(locale))
    }

    /// Formats as the rate-summary label ("1 USDc = X").
    ///
    /// **2–4 fractional digits.** Quick-glance label, not source of truth —
    /// the underlying `Decimal` precision is preserved on the rate object,
    /// this is purely the displayed form.
    ///
    /// Used by the View at render time; the VM never stores this string.
    func formattedAsRate(locale: Locale = .current) -> String {
        formatted(.number.precision(.fractionLength(2...4)).locale(locale))
    }
}
