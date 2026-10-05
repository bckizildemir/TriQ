import SwiftUI

struct TrioQuestionFeedCard: View {
    @EnvironmentObject private var categoryModel: CategoryModel
    let question: Question
    @ObservedObject var questionModel: QuestionModel
    let onQuestionTap: (ExpandedQuestionState) -> Void

    private var answeredCount: Int {
        questionModel.myAnswers(for: question.id).filter { !$0.isEmpty }.count
    }

    var body: some View {
        Button {
            onQuestionTap(
                ExpandedQuestionState(
                    question: question,
                    headerStyle: .plain
                )
            )
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                headerRow
                questionText
                QuestionCreatorAttributionView(question: question)
                footerRow
            }
            .padding(18)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(question.text)
        .accessibilityHint(String(localized: "ai.trioFeed.accessibilityHint"))
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(categoryModel.title(for: question.category), systemImage: categoryModel.iconName(for: question.category))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Text(question.trioCreatedAtString)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var questionText: some View {
        Text(question.text)
            .font(.title3.bold())
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerRow: some View {
        HStack(spacing: 12) {
            Label(
                answeredCount == 3
                    ? String(localized: "ai.trioFeed.answered")
                    : String(format: String(localized: "ai.trioFeed.answersReady"), locale: AppLocalization.currentLocale, answeredCount),
                systemImage: answeredCount == 3 ? "checkmark.circle.fill" : "square.and.pencil"
            )
            .font(.footnote)
            .foregroundStyle(answeredCount == 3 ? .green : .secondary)

            if question.totalRespondents > 0 {
                Label(String(format: String(localized: "ai.trioFeed.respondentsCount"), locale: AppLocalization.currentLocale, question.totalRespondents), systemImage: "person.2.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(.tertiary)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(Color.theme.secondaryBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.theme.border.opacity(0.35), lineWidth: 1)
            )
    }
}
