import SwiftUI

/// Main exchange calculator screen. Hosts the USDc + foreign input rows,
/// the swap button between them, the rate summary line, and loading/error
/// overlays.
///
/// Consumes an `ExchangeCalculatorViewModel` injected from the parent so
/// previews and tests can swap the service backing.
struct ExchangeCalculatorView: View {
    @State var viewModel: ExchangeCalculatorViewModel
    @State private var isCurrencyPickerPresented: Bool = false

    /// Bumped when the user taps Retry. Combined with the selected
    /// currency code to form the `.task(id:)` key, so Retry drives a
    /// fresh load through the same structured-concurrency boundary
    /// instead of spawning a detached `Task { }` from the button.
    @State private var retryToken: Int = 0

    private static let usdcCurrency = Currency(
        code: "USDc",
        flagEmoji: "🇺🇸",
        displayName: "USD Coin"
    )

    init(viewModel: ExchangeCalculatorViewModel? = nil) {
        self._viewModel = State(wrappedValue: viewModel ?? ExchangeCalculatorViewModel())
    }

    /// Composite key for `.task(id:)` — changing either component
    /// cancels the old task and starts a new one.
    private var loadTaskID: String {
        "\(viewModel.selectedCurrency.code)#\(retryToken)"
    }

    var body: some View {
        ZStack {
            Color(hex: 0xF8F8F8)
                .ignoresSafeArea()
                // Tap the background to dismiss the numeric keyboard;
                // decimalPad has no Return key of its own.
                .contentShape(Rectangle())
                .onTapGesture { Self.dismissKeyboard() }

            // ScrollView so the content can grow vertically at large
            // Dynamic Type sizes without pushing the rate summary or
            // input rows off-screen.
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    amountStack
                }
                .padding(.top, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            if let message = viewModel.errorMessage {
                errorBanner(message: message)
            }

            if viewModel.isLoading {
                ProgressView()
                    .accessibilityIdentifier("loadingIndicator")
                    .accessibilityLabel("Loading exchange rates")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { Self.dismissKeyboard() }
                    .accessibilityIdentifier("keyboardDone")
            }
        }
        // Load the currency list once on appear.
        .task {
            await viewModel.loadAvailableCurrencies()
        }
        // Rate fetch is keyed by (selected currency, retry token). Either
        // a currency change or a Retry tap bumps the key, which cancels
        // the prior task and starts a new one. Cancellation is fully
        // structural — no manual Task spawning anywhere in this view.
        .task(id: loadTaskID) {
            await viewModel.loadRates()
        }
        .sheet(isPresented: $isCurrencyPickerPresented) {
            // Bind selection through a wrapper that routes writes through
            // `viewModel.selectCurrency(_:)` so the VM's side effects
            // (invalidating stale rate, clearing foreign amount) run.
            CurrencyPickerSheet(
                currencies: viewModel.availableCurrencies,
                selectedCurrency: Binding(
                    get: { viewModel.selectedCurrency },
                    set: { viewModel.selectCurrency($0) }
                )
            )
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exchange calculator")
                .font(.largeTitle.bold())
                .foregroundStyle(Color(hex: 0x2C2C2E))
                .accessibilityIdentifier("exchangeTitle")

            rateSummary
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var rateSummary: some View {
        if let rate = viewModel.currentRate {
            VStack(alignment: .leading, spacing: 2) {
                Text("1 USDc = \(rate.bid.formattedAsRate()) \(viewModel.selectedCurrency.code)")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(hex: 0x22D081))
                    .accessibilityIdentifier("rateSummaryLabel")
                if let published = rate.publishedAt {
                    HStack(spacing: 8) {
                        Text("Updated \(published.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(Color(hex: 0x8E8E93))
                            .accessibilityIdentifier("rateFreshnessLabel")
                        Button {
                            retryToken &+= 1
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                                .symbolEffect(
                                    .rotate,
                                    options: .repeat(.continuous),
                                    isActive: viewModel.isLoading
                                )
                                // 44pt frame for the HIG-minimum tap target;
                                // the glyph stays caption-sized.
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color(hex: 0x22D081))
                        .disabled(viewModel.isLoading)
                        .accessibilityIdentifier("rateRefreshButton")
                        .accessibilityLabel("Refresh exchange rate")
                    }
                }
            }
        } else {
            Text(" ")
                .accessibilityIdentifier("rateSummaryLabel")
        }
    }

    private var amountStack: some View {
        ZStack {
            VStack(spacing: 16) {
                if viewModel.isSwapped {
                    foreignRow
                    usdcRow
                } else {
                    usdcRow
                    foreignRow
                }
            }
            Button {
                viewModel.swapCurrencies()
            } label: {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(CircleIconStyle())
            .accessibilityIdentifier("swapButton")
            .accessibilityLabel("Swap currencies")
        }
    }

    private var usdcRow: some View {
        CurrencyInputRow(
            currency: Self.usdcCurrency,
            isTappable: false,
            amount: Binding(
                get: { viewModel.usdcAmount },
                set: { viewModel.usdcAmountChanged($0) }
            ),
            amountFieldIdentifier: "usdcAmountField"
        )
    }

    private var foreignRow: some View {
        CurrencyInputRow(
            currency: viewModel.selectedCurrency,
            isTappable: true,
            amount: Binding(
                get: { viewModel.foreignAmount },
                set: { viewModel.foreignAmountChanged($0) }
            ),
            amountFieldIdentifier: "foreignAmountField",
            currencyLabelIdentifier: "foreignCurrencyPicker",
            isCurrencyPickerPresented: $isCurrencyPickerPresented
        )
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
                Spacer(minLength: 8)
                Button("Retry") {
                    viewModel.errorMessage = nil
                    // Bumping the token changes the .task(id:) key;
                    // SwiftUI cancels any in-flight task and starts a
                    // fresh loadRates under the same structured-
                    // concurrency boundary. No Task { } here.
                    retryToken &+= 1
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.white.opacity(0.25), in: Capsule())
                .accessibilityIdentifier("errorRetry")
                Button {
                    viewModel.errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.9))
                }
                .accessibilityLabel("Dismiss error")
                .accessibilityIdentifier("errorDismiss")
            }
            .padding(12)
            .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            // `children: .contain` so the Retry / Dismiss buttons keep
            // their own accessibilityIdentifiers (the container's id
            // would otherwise cascade and override them).
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("errorBanner")
            Spacer()
        }
        .padding(.top, 96)
    }

    // MARK: - Keyboard

    /// Resign first responder on any currently-focused UITextField.
    /// Used by the background tap handler and the keyboard toolbar's
    /// Done button since `decimalPad` has no built-in return key.
    private static func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
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
