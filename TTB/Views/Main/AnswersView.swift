import SwiftUI

// NavigationStack içermeyen içerik view'i — ProfileView'den push ile kullanılır
struct AnswersContentView: View {
    @StateObject private var answerModel = AnswerModel()
    @EnvironmentObject private var badgeModel: BadgeModel
    @EnvironmentObject private var questionModel: QuestionModel
    @State private var presentedQuestion: ExpandedQuestionState?

    private let expansionSourceID = "answers"

    /// Questions the current user has fully answered (all 3 slots filled), sorted newest first.
    ///
    /// Decorated in a single pass: the previous version read the answer record once in the filter
    /// and twice more per comparison inside the sort.
    private var answeredQuestions: [Question] {
        questionModel.questions
            .compactMap { question -> (question: Question, answeredAt: Date)? in
                guard let answer = questionModel.currentUserAnswers[question.id],
                      answer.answers.reduce(into: 0, { count, slot in
                          if !slot.isEmpty { count += 1 }
                      }) == 3
                else { return nil }
                return (question, answer.answeredAt)
            }
            .sorted { $0.answeredAt > $1.answeredAt }
            .map(\.question)
    }

    var body: some View {
        content
        .background(Color.theme.background)
        .navigationTitle(String(localized: "main.answers.title"))
        .toolbarTitleDisplayMode(.inline)
        .refreshable {
            await answerModel.fetchStatistics()
        }
        .fullScreenCover(item: $presentedQuestion) { expandedState in
            QuestionDetailModalShell(
                expandedState: expandedState,
                model: questionModel,
                badgeModel: badgeModel
            )
        }
        .alert(
            String(localized: "common.error.title"),
            isPresented: Binding(
                get: { questionModel.error != nil },
                set: { if !$0 { questionModel.error = nil } }
            ),
            actions: {
                Button(String(localized: "common.ok")) { questionModel.error = nil }
            },
            message: {
                if let error = questionModel.error { Text(error) }
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        if questionModel.isLoading {
            loadingView
        } else {
            // Derived once and threaded down rather than read for the empty check and again for the
            // `ForEach`.
            let questions = answeredQuestions
            if questions.isEmpty {
                emptyStateView
            } else {
                questionsList(questions)
            }
        }
    }

    private var loadingView: some View {
        ProgressView(String(localized: "main.answers.loading"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 100)
            .accessibilityLabel(String(localized: "main.answers.loading"))
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 50))
                .foregroundColor(.gray)
                .accessibilityHidden(true)

            Text(String(localized: "main.answers.emptyTitle"))
                .font(.headline)
                .foregroundColor(.gray)

            Text(String(localized: "main.answers.emptyBody"))
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(String(localized: "main.answers.emptyTitle")). \(String(localized: "main.answers.emptyBody"))"
        )
    }

    private func questionsList(_ questions: [Question]) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let error = answerModel.error {
                    errorView(message: error)
                }

                ForEach(questions) { question in
                    AnsweredQuestionCard(
                        question: question,
                        questionModel: questionModel,
                        sourceID: expansionSourceID,
                        onTap: {
                            presentedQuestion = ExpandedQuestionState(
                                question: question,
                                headerStyle: .answered
                            )
                        }
                    )
                }
            }
            .padding(.vertical)
        }
    }

    private func errorView(message: String) -> some View {
        Text(message)
            .foregroundColor(.red)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
    }
}

// Standalone wrapper — bağımsız kullanım ve Preview için
struct AnswersView: View {
    var body: some View {
        NavigationStack {
            AnswersContentView()
        }
    }
}

struct AnsweredQuestionCard: View {
    @EnvironmentObject private var categoryModel: CategoryModel
    let question: Question
    let questionModel: QuestionModel
    let sourceID: String
    var onTap: (() -> Void)?

    var body: some View {
        QuestionCard(
            question: question,
            model: questionModel,
            headerStyle: .plain,
            sourceID: sourceID,
            onTap: onTap,
            showsShareButton: true,
            presentationStyle: .pagedFeed,
            categoryColor: categoryModel.color(for: question.category)
        )
        .padding(.horizontal)
    }
}

#Preview {
    AnswersView()
        .environmentObject(FavoriteStore.previews)
        .environmentObject(QuestionModel())
        .environmentObject(CategoryModel(localCategories: Category.defaultCategories))
        .environmentObject(BadgeModel())
}
