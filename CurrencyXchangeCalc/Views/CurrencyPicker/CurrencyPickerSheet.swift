import SwiftUI

/// Bottom sheet that lets the user pick a foreign currency.
///
/// Uses the SwiftUI-idiomatic data-flow shape: a `@Binding` to the
/// selected currency (the parent's state is the single source of truth),
/// and `@Environment(\.dismiss)` for self-dismissal — no event-callback
/// closures on the boundary. The parent wraps `viewModel.selectCurrency(_:)`
/// in the binding's setter so the VM's side effects (invalidating stale
/// rate, clearing foreign amount) happen on selection.
struct CurrencyPickerSheet: View {
    let currencies: [Currency]
    @Binding var selectedCurrency: Currency

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(currencies) { currency in
                Button {
                    selectedCurrency = currency
                    dismiss()
                } label: {
                    CurrencyPickerRow(
                        currency: currency,
                        isSelected: currency == selectedCurrency
                    )
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Select currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("currencyPickerCancel")
                }
            }
        }
        .accessibilityIdentifier("currencyPickerSheet")
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    @Previewable @State var selected = Currency.fallbackList[0]
    Color.gray
        .sheet(isPresented: .constant(true)) {
            CurrencyPickerSheet(
                currencies: Currency.fallbackList,
                selectedCurrency: $selected
            )
        }
}
