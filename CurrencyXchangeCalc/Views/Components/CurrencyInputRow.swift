import SwiftUI

/// A single currency input row showing a flag, currency code, and amount field.
struct CurrencyInputRow: View {
    let currency: Currency
    let isTappable: Bool
    @Binding var amount: String
    var onTapCurrency: (() -> Void)?

    var body: some View {
        Text(currency.code)  // TODO: implement in Phase 3
    }
}
