import SwiftUI

/// Main exchange calculator screen. Hosts the USDc + foreign input rows,
/// the swap button between them, the rate summary line, and loading/error
/// overlays.
///
/// Consumes an `ExchangeCalculatorViewModel` injected from the parent so
/// previews and tests can swap the service backing.
struct ExchangeCalculatorView: View {
    @State var viewModel: ExchangeCalculatorViewModel

    private static let usdcCurrency = Currency(
        code: "USDc",
        flagEmoji: "🇺🇸",
        displayName: "USD Coin"
    )

    init(viewModel: ExchangeCalculatorViewModel? = nil) {
        self._viewModel = State(wrappedValue: viewModel ?? ExchangeCalculatorViewModel())
    }

    var body: some View {
        ZStack {
            Color(hex: 0xF8F8F8).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                header
                amountStack
                Spacer()
            }
            .padding(.top, 24)

            if let message = viewModel.errorMessage {
                errorBanner(message: message)
            }

            if viewModel.isLoading {
                ProgressView()
                    .accessibilityIdentifier("loadingIndicator")
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exchange")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color(hex: 0x2C2C2E))
                .accessibilityIdentifier("exchangeTitle")

            rateSummary
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var rateSummary: some View {
        if let rate = viewModel.currentRate {
            Text("1 USDc = \(formattedRate(rate.bid)) \(viewModel.selectedCurrency.code)")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(hex: 0x22D081))
                .accessibilityIdentifier("rateSummaryLabel")
        } else {
            Text(" ")
                .accessibilityIdentifier("rateSummaryLabel")
        }
    }

    private var amountStack: some View {
        ZStack {
            VStack(spacing: 16) {
                CurrencyInputRow(
                    currency: Self.usdcCurrency,
                    isTappable: false,
                    amount: Binding(
                        get: { viewModel.usdcAmount },
                        set: { viewModel.usdcAmountChanged($0) }
                    ),
                    amountFieldIdentifier: "usdcAmountField"
                )
                CurrencyInputRow(
                    currency: viewModel.selectedCurrency,
                    isTappable: true,
                    amount: Binding(
                        get: { viewModel.foreignAmount },
                        set: { viewModel.foreignAmountChanged($0) }
                    ),
                    amountFieldIdentifier: "foreignAmountField",
                    currencyLabelIdentifier: "foreignCurrencyPicker",
                    onTapCurrency: {
                        // Wired in Phase 4 when the picker sheet lands.
                    }
                )
            }
            SwapButton(action: { viewModel.swapCurrencies() })
        }
    }

    private func errorBanner(message: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                Text(message)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Spacer()
                Button {
                    viewModel.errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.9))
                }
                .accessibilityLabel("Dismiss error")
            }
            .padding(12)
            .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .accessibilityIdentifier("errorBanner")
            Spacer()
        }
        .padding(.top, 96)
    }

    // MARK: - Formatting

    private func formattedRate(_ rate: Decimal) -> String {
        rate.formatted(.number.precision(.fractionLength(2...4)))
    }
}

#Preview("With rate") {
    let mock = MockPreviewService()
    let vm = ExchangeCalculatorViewModel(service: mock, selectedCurrency: Currency.fallbackList[0])
    return ExchangeCalculatorView(viewModel: vm)
        .task { await vm.loadRates() }
}

#Preview("Empty") {
    ExchangeCalculatorView()
}

// MARK: - Preview-only service

/// Value-type preview service. Inherently `Sendable` via struct, so no
/// `@unchecked` needed.
private struct MockPreviewService: ExchangeRateServiceProtocol {
    func fetchRates(for currencies: [String]) async throws -> [ExchangeRate] {
        [
            ExchangeRate(
                ask: Decimal(string: "18.4105")!,
                bid: Decimal(string: "18.4069")!,
                book: "usdc_mxn",
                date: ""
            )
        ]
    }
    func fetchCurrencies() async throws -> [String] {
        Currency.fallbackList.map(\.code)
    }
}
