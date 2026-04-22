import SwiftUI

/// Bottom sheet for selecting a foreign currency.
struct CurrencyPickerSheet: View {
    let currencies: [Currency]
    let selectedCurrency: Currency
    let onSelect: (Currency) -> Void

    var body: some View {
        List(currencies) { currency in
            CurrencyPickerRow(currency: currency, isSelected: currency == selectedCurrency)
                .onTapGesture { onSelect(currency) }
        }
        // TODO: implement in Phase 4
    }
}

#Preview {
//    CurrencyPickerSheet(currencies: [.fallbackList.first!], selectedCurrency: .fallbackList.first!) { _ in
//        
//    }
}
