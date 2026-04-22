import SwiftUI

/// A single row in the currency picker list.
struct CurrencyPickerRow: View {
    let currency: Currency
    let isSelected: Bool // Should this be state based?

    var body: some View {
        HStack {
            Text(currency.flagEmoji)
            Text(currency.code)
            Text(currency.displayName)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
        // TODO: style in Phase 4
    }
}
