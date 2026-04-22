import SwiftUI

/// App root. Phase 3 hosts the calculator directly; Phase 5 will inject
/// a configured `LiveExchangeRateService` here.
struct ContentView: View {
    var body: some View {
        ExchangeCalculatorView()
    }
}

#Preview {
    ContentView()
}
