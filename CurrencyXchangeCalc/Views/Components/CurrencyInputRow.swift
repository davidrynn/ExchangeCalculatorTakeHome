import SwiftUI

/// A single currency input row — flag + code on the left, amount field on the right.
///
/// The `amount` binding is expected to be a two-way binding that routes
/// writes through the owning ViewModel (e.g. its setter calls
/// `usdcAmountChanged`), so there is no divergence between the
/// `TextField`'s internal state and the VM state — especially important
/// after swaps and currency changes that mutate the VM externally.
///
/// The currency side is only tappable when `isTappable` is `true` (foreign
/// row). The USDc row is non-tappable.
struct CurrencyInputRow: View {
    let currency: Currency
    let isTappable: Bool
    @Binding var amount: String

    /// Optional stable identifier for the amount `TextField`. Used by UI tests.
    let amountFieldIdentifier: String

    /// Optional stable identifier for the currency label (foreign row).
    let currencyLabelIdentifier: String?

    let onTapCurrency: (() -> Void)?

    init(
        currency: Currency,
        isTappable: Bool,
        amount: Binding<String>,
        amountFieldIdentifier: String,
        currencyLabelIdentifier: String? = nil,
        onTapCurrency: (() -> Void)? = nil
    ) {
        self.currency = currency
        self.isTappable = isTappable
        self._amount = amount
        self.amountFieldIdentifier = amountFieldIdentifier
        self.currencyLabelIdentifier = currencyLabelIdentifier
        self.onTapCurrency = onTapCurrency
    }

    var body: some View {
        HStack(spacing: 16) {
            currencySide
            TextField("0.00", text: $amount)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.weight(.bold))
                .foregroundStyle(Color(.label))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityIdentifier(amountFieldIdentifier)
                .accessibilityLabel(accessibilityAmountLabel)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(height: 66)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var currencySide: some View {
        let content = HStack(spacing: 8) {
            Text(currency.flagEmoji)
                .font(.system(size: 16))
            Text(currency.code)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(.label))
            if isTappable {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(.label))
            }
        }
        .accessibilityElement(children: .combine)

        if isTappable, let onTapCurrency {
            let button = Button(action: onTapCurrency) {
                content
            }
            .buttonStyle(.plain)
            // Attach the identifier to the tappable Button so UI tests
            // can locate it via `app.buttons["foreignCurrencyPicker"]`.
            if let id = currencyLabelIdentifier {
                button.accessibilityIdentifier(id)
            } else {
                button
            }
        } else {
            if let id = currencyLabelIdentifier {
                content.accessibilityIdentifier(id)
            } else {
                content
            }
        }
    }

    private var accessibilityAmountLabel: String {
        currency.code == "USDc" ? "USDc amount" : "\(currency.code) amount"
    }
}

#Preview {
    @Previewable @State var usdc = "1.00"
    @Previewable @State var foreign = "18.41"

    VStack(spacing: 16) {
        CurrencyInputRow(
            currency: Currency(code: "USDc", flagEmoji: "🇺🇸", displayName: "USD Coin"),
            isTappable: false,
            amount: $usdc,
            amountFieldIdentifier: "usdcAmountField"
        )
        CurrencyInputRow(
            currency: Currency.fallbackList[0],
            isTappable: true,
            amount: $foreign,
            amountFieldIdentifier: "foreignAmountField",
            currencyLabelIdentifier: "foreignCurrencyPicker",
            onTapCurrency: { }
        )
    }
    .padding(.vertical)
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}
