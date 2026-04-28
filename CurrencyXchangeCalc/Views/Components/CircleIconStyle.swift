import SwiftUI

/// Small circular icon button: white SF Symbol on a green disc with a
/// thick light-grey halo. Used as the swap button between currency rows.
///
/// The icon is supplied by the call site (`configuration.label`), so this
/// style is reusable for any 24pt circular icon button — not just the
/// down-arrow swap action.
struct CircleIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Color(hex: 0x22D081), in: Circle())
            .overlay(
                Circle()
                    .stroke(Color(hex: 0xF4F4F4), lineWidth: 6)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

#Preview {
    Button {
    } label: {
        Image(systemName: "arrow.down")
    }
    .buttonStyle(CircleIconStyle())
    .padding()
    .background(Color.gray)
}
