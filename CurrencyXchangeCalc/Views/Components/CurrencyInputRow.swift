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
    /// Write-only outbound signal — setting `true` asks the parent to
    /// present the picker. `nil` for non-tappable rows (USDc) since they
    /// never present a picker; an optional `Binding` stays honest about
    /// that absence rather than carrying a `.constant(false)` stub.
    let isCurrencyPickerPresented: Binding<Bool>?
    let amountFieldIdentifier: String
    let currencyLabelIdentifier: String?

    init(
        currency: Currency,
        isTappable: Bool,
        amount: Binding<String>,
        amountFieldIdentifier: String,
        currencyLabelIdentifier: String? = nil,
        isCurrencyPickerPresented: Binding<Bool>? = nil
    ) {
        self.currency = currency
        self.isTappable = isTappable
        self._amount = amount
        self.amountFieldIdentifier = amountFieldIdentifier
        self.currencyLabelIdentifier = currencyLabelIdentifier
        self.isCurrencyPickerPresented = isCurrencyPickerPresented
    }

    var body: some View {
        // `alignment: .top` so currencySide + symbol stay anchored to
        // the row's top edge as the TextField wraps to additional lines.
        HStack(alignment: .top, spacing: 16) {
            currencySide
            Spacer(minLength: 0)
            // `accessibilityHidden` so VoiceOver doesn't double-announce
            // the currency alongside the field's label.
            Text(currency.symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(Color(.label))
                .accessibilityHidden(true)
            // Multi-line input — `axis: .vertical` + `lineLimit(1...)`
            // lets the field grow vertically rather than overflow the
            // row horizontally when the value is very long or Dynamic
            // Type is at an accessibility size. The outer ScrollView
            // absorbs anything taller than the screen.
            TextField("0.00", text: $amount, axis: .vertical)
                .keyboardType(.decimalPad)
                // Trailing so the value anchors to the row's right
                // edge; the symbol sits on the field's leading edge,
                // creating a small gap when content is short and
                // closing as content grows.
                .multilineTextAlignment(.trailing)
                .font(.body.weight(.bold))
                .foregroundStyle(Color(.label))
                .lineLimit(1...)
                .accessibilityIdentifier(amountFieldIdentifier)
                .accessibilityLabel(accessibilityAmountLabel)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(minHeight: 66)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var currencySide: some View {
        // `lineLimit(1)` on the code text + `layoutPriority(1)` on the
        // outer HStack keep the currency label intact at large Dynamic
        // Type sizes — the multi-line TextField cluster yields width
        // first instead.
        let content = HStack(spacing: 8) {
            Text(currency.flagEmoji)
                .font(.system(size: 16))
            Text(currency.code)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(.label))
                .lineLimit(1)
            if isTappable {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(.label))
            }
        }
        .layoutPriority(1)
        .accessibilityElement(children: .combine)

        if isTappable {
            let button = Button {
                // Always present — never toggle. The sheet drives its
                // own dismissal, so toggling here could dismiss a sheet
                // that was just opened.
                isCurrencyPickerPresented?.wrappedValue = true
            } label: {
                content
            }
            .buttonStyle(.plain)
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
    @Previewable @State var pickerPresented: Bool = false

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
            isCurrencyPickerPresented: $pickerPresented
        )
    }
    .padding(.vertical)
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}
