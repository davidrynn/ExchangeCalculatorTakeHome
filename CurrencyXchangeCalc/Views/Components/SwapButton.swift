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
            Image(systemName: "arrow.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color(hex: 0x22D081), in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color(hex: 0xF4F4F4), lineWidth: 6)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("swapButton")
        .accessibilityLabel("Swap currencies")
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    SwapButton(action: {})
        .padding()
        .background(Color.gray)
}
