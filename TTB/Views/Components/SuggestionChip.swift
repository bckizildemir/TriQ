import SwiftUI

struct SuggestionChip: View {
    let text: String
    let isSelected: Bool
    var accessibilityIdentifier: String?
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(minWidth: 100, maxWidth: .infinity, minHeight: 38)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.theme.secondaryBackground)
                )
                .foregroundStyle(isSelected ? .white : .primary)
                .overlay(
                    Capsule()
                        .stroke(Color.accentColor.opacity(isSelected ? 0 : 0.3), lineWidth: 1)
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .modifier(OptionalAccessibilityIdentifier(identifier: accessibilityIdentifier))
        .accessibilityLabel("Suggestion: \(text)")
        .accessibilityHint("Double tap to select this question variation")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !reduceMotion {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    if !reduceMotion {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = false
                        }
                    }
                }
        )
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        SuggestionChip(
            text: "Best 3 HP movies?",
            isSelected: false,
            onTap: {}
        )

        SuggestionChip(
            text: "Your 3 favorite characters in HP books?",
            isSelected: true,
            onTap: {}
        )
    }
    .padding()
}
