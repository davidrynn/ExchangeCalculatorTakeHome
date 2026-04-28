import SwiftUI

/// A single row in the currency picker list — flag + ISO code, with a
/// trailing selection indicator.
///
/// Pure presentation — `isSelected` is passed in by the parent
/// (`CurrencyPickerSheet`), which owns the selection state. A row is
/// always a reflection of external state, never a mutable container, so
/// `Bool` is correct here (no `@State` or `@Binding` needed).
///
/// Trailing indicator:
/// - Selected: solid green circle with a white checkmark
///   (`checkmark.circle.fill` in `#22D081`).
/// - Unselected: empty circle outline (`circle` in light gray).
struct CurrencyPickerRow: View {
    let currency: Currency
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(currency.flagEmoji)
                .font(.system(size: 22))
            Text(currency.code)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(hex: 0x2C2C2E))
            Spacer()
            selectionIndicator
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.white, Color(hex: 0x22D081))
        } else {
            Image(systemName: "circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color(hex: 0xD0D0D0))
        }
    }
}

#Preview {
    List {
        CurrencyPickerRow(currency: Currency.fallbackList[0], isSelected: true)
        CurrencyPickerRow(currency: Currency.fallbackList[1], isSelected: false)
    }
    .listStyle(.plain)
}
