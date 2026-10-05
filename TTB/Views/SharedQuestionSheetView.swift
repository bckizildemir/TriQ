import SwiftUI

struct SharedQuestionSheetView: View {
    let questionId: String

    @EnvironmentObject private var questionModel: QuestionModel
    @Environment(\.dismiss) private var dismiss

    @State private var question: Question?
    @State private var isLoading = true
    @State private var errorMessage: String?

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
                    VStack(spacing: 16) {
                        if isLoading {
                            ProgressView(String(localized: "common.loading"))
                        } else {
                            Image(systemName: "questionmark.circle")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)

                            Text(errorMessage ?? "Soru bulunamadi.")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)

                            Button(String(localized: "common.close")) {
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(24)
                    .navigationTitle("TTB")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .task(id: questionId) {
            await loadQuestion()
        }
    }

    private func loadQuestion() async {
        isLoading = true
        errorMessage = nil

        if let existingQuestion = questionModel.question(withID: questionId) {
            question = existingQuestion
            isLoading = false
            return
        }

        do {
            question = try await questionModel.fetchSharedQuestion(id: questionId)
        } catch {
            errorMessage = "Soru bulunamadi veya artik yayinda degil."
        }

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
