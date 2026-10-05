import SwiftUI

struct QuestionPreviewCard: View {
    @Binding var questionText: String
    let categoryName: String
    let categoryIcon: String
    @FocusState private var isQuestionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(localized: "ai.trioComposer.prompt"))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "ai.trioComposer.prompt"))

            VStack(alignment: .leading, spacing: 16) {
                TextField(
                    String(localized: "ai.trioComposer.promptPlaceholder"),
                    text: $questionText,
                    axis: .vertical
                )
                .focused($isQuestionFocused)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2...5)
                .textInputAutocapitalization(.sentences)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(String(localized: "ai.trioComposer.prompt"))
                .accessibilityIdentifier("trio-draft-field")

                HStack(spacing: 12) {
                    Label(categoryName, systemImage: categoryIcon)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Label("0/3", systemImage: "square.and.pencil")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.theme.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                Color.accentColor.opacity(isQuestionFocused ? 0.45 : 0.18),
                                lineWidth: isQuestionFocused ? 1.5 : 1
                            )
                    )
            )

            Text(String(localized: "ai.trioComposer.promptHint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.theme.secondaryBackground)
        )
    }
}

#Preview {
    QuestionPreviewCard(
        questionText: .constant("What are the 3 best Harry Potter movies?"),
        categoryName: "Daily",
        categoryIcon: "target"
    )
    .padding()
}
