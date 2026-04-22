import SwiftUI

/// Circular green button that swaps the two currency fields.
struct SwapButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.arrow.down")  // TODO: style in Phase 3
        }
    }
}
