import SwiftUI

struct SharedQuestionSheetView: View {
    let questionId: String

    @EnvironmentObject private var questionModel: QuestionModel
    @Environment(\.dismiss) private var dismiss

    @State private var question: Question?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let question {
                QuestionDetailModalShell(
                    expandedState: ExpandedQuestionState(
                        question: question,
                        headerStyle: .plain
                    ),
                    model: questionModel,
                    onClose: { dismiss() }
                )
            } else {
                NavigationStack {
                    Group {
                        if isLoading {
                            ProgressView(String(localized: "common.loading"))
                        } else {
                            ContentUnavailableView(
                                String(localized: "sharedQuestion.notFound.title"),
                                systemImage: "questionmark.circle",
                                description: Text(String(localized: "sharedQuestion.notFound.description"))
                            )
                        }
                    }
                    .navigationTitle(String(localized: "sharedQuestion.title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "common.close")) {
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
        .task(id: questionId) {
            await loadQuestion()
        }
    }

    private func loadQuestion() async {
        isLoading = true

        if let existingQuestion = questionModel.question(withID: questionId) {
            question = existingQuestion
            isLoading = false
            return
        }

        // A failed fetch leaves `question` nil, which shows the not-found state.
        question = try? await questionModel.fetchSharedQuestion(id: questionId)

        isLoading = false
    }
}

#Preview {
    SharedQuestionSheetView(questionId: Question.sampleQuestions[0].id)
        .environmentObject(QuestionModel(localQuestions: Question.sampleQuestions))
        .environmentObject(AuthModel())
        .environmentObject(FavoriteStore.previews)
        .environmentObject(GuestFavoriteModel())
        .environmentObject(QuestionListStore(localLists: []))
}
