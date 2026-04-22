import SwiftUI

/// App root container. Receives the composition-root view model from
/// `CurrencyXchangeCalcApp` (live service wired) or uses a default for
/// previews.
struct ContentView: View {
    let viewModel: ExchangeCalculatorViewModel?

    init(viewModel: ExchangeCalculatorViewModel? = nil) {
        self.viewModel = viewModel
    }

    var body: some View {
        ExchangeCalculatorView(viewModel: viewModel)
    }
}

#Preview {
    ContentView()
}
