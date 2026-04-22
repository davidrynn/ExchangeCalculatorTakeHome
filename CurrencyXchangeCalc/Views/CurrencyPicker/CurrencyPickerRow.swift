import SwiftUI

/// A single row in the currency picker list.
///
/// Pure presentation — `isSelected` is passed in by the parent
/// (`CurrencyPickerSheet`), which owns the selection state. A row is
/// always a reflection of external state, never a mutable container, so
/// `Bool` is correct here (no `@State` or `@Binding` needed).
struct CurrencyPickerRow: View {
    let currency: Currency
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(currency.flagEmoji)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(currency.code)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(.label))
                Text(currency.displayName)
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(hex: 0x22D081))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("currencyPickerRow.\(currency.code)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    List {
        CurrencyPickerRow(currency: Currency.fallbackList[0], isSelected: true)
        CurrencyPickerRow(currency: Currency.fallbackList[1], isSelected: false)
    }
}
