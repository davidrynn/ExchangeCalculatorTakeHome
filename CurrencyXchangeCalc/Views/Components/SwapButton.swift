import SwiftUI

/// Circular green button that swaps the two currency fields.
///
/// FOLLOWUP: Evaluate moving `action` from an init parameter to an
/// EnvironmentValues-based modifier (`.onSwap { ... }`) in the style of
/// Apple's `.refreshable` / `.onSubmit` / `.dismiss`. Defer until there is
/// a concrete reusability or composition need — for a single call site the
/// plain `Button(action:)` shape is simpler and matches Apple's own
/// `Button` API.
struct SwapButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.arrow.down")  // TODO: style in Phase 3
        }
    }
}
