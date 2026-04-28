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

    /// Currencies sorted A→Z by ISO code so the user can scan the list
    /// predictably regardless of the order the API (or fallback) returned.
    /// `localizedStandardCompare` keeps mixed-case codes like `EURc`
    /// alongside `EUR` instead of pushed to the end of the alphabet.
    private var sortedCurrencies: [Currency] {
        currencies.sorted {
            $0.code.localizedStandardCompare($1.code) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List(sortedCurrencies) { currency in
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
                .accessibilityIdentifier("currencyPickerRow.\(currency.code)")
                .listRowBackground(Color.white)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .navigationTitle("Choose currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color(hex: 0x2C2C2E))
                    }
                    .accessibilityLabel("Close")
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
