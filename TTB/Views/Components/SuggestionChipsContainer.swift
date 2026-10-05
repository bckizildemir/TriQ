import SwiftUI

struct SuggestionChipsContainer: View {
    let suggestions: [String]
    let selectedSuggestion: String?
    let isLoading: Bool
    var isSelectionDisabled: Bool = false
    let onSelect: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(String(localized: "ai.suggestions.title"))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                isLoading
                    ? String(localized: "ai.suggestions.accessibility.loading")
                    : String(localized: "ai.suggestions.accessibility.ready")
            )

            if !suggestions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                        SuggestionRow(
                            text: suggestion,
                            isSelected: selectedSuggestion == suggestion,
                            revealText: !reduceMotion,
                            revealDelay: Double(index) * 0.18,
                            accessibilityIdentifier: "trio-suggestion-\(index)",
                            onTap: { onSelect(suggestion) }
                        )
                        .disabled(isSelectionDisabled)
                        .opacity(isSelectionDisabled ? 0.48 : 1)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.9)),
                            removal: .opacity
                        ))
                        .animation(
                            reduceMotion ? nil : .easeOut.delay(Double(index) * 0.05),
                            value: suggestions
                        )
                    }
                }
            } else if !isLoading {
                Text(String(localized: "ai.suggestions.empty"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 19)
                            .fill(Color.theme.background.opacity(0.75))
                            .frame(height: 68)
                            .overlay(
                                RoundedRectangle(cornerRadius: 19)
                                    .stroke(Color.theme.border.opacity(0.25), lineWidth: 1)
                            )
                            .opacity(0.64)
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }
}

private struct SuggestionRow: View {
    let text: String
    let isSelected: Bool
    let revealText: Bool
    let revealDelay: Double
    let accessibilityIdentifier: String
    let onTap: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                ProgressiveSuggestionText(
                    text: text,
                    shouldReveal: revealText,
                    initialDelay: revealDelay
                )
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(rowBackground)
            .overlay(rowBorder)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(text)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.theme.background.opacity(0.75))
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                isSelected || differentiateWithoutColor
                    ? Color.accentColor.opacity(isSelected ? 0.7 : 0.25)
                    : Color.theme.border.opacity(0.28),
                lineWidth: isSelected ? 1.4 : 1
            )
    }
}

private struct ProgressiveSuggestionText: View {
    let text: String
    let shouldReveal: Bool
    let initialDelay: Double

    @State private var visibleCharacterCount = 0

    private var visibleText: String {
        guard shouldReveal else { return text }
        return String(text.prefix(visibleCharacterCount))
    }

    var body: some View {
        Text(visibleText)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .task(id: text) {
                await reveal()
            }
    }

    @MainActor
    private func reveal() async {
        guard shouldReveal else {
            visibleCharacterCount = text.count
            return
        }

        visibleCharacterCount = 0
        guard text.isEmpty == false else { return }
        let delayNanoseconds = UInt64(initialDelay * 1_000_000_000)
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }

        for count in 1...text.count {
            guard Task.isCancelled == false else { return }
            visibleCharacterCount = count
            try? await Task.sleep(nanoseconds: 12_000_000)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SuggestionChipsContainer(
            suggestions: [
                "What are your 3 favorite moments from the Harry Potter movies and why?",
                "Which 3 basketball players changed how you understand the game?",
                "What 3 meals would you choose for a perfect weekend with friends?"
            ],
            selectedSuggestion: nil,
            isLoading: false,
            onSelect: { _ in }
        )

        SuggestionChipsContainer(
            suggestions: [],
            selectedSuggestion: nil,
            isLoading: true,
            isSelectionDisabled: true,
            onSelect: { _ in }
        )
    }
    .padding()
}
