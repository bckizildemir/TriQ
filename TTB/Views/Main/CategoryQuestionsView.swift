import SwiftUI

struct CategoryQuestionsView: View {
    @EnvironmentObject private var categoryModel: CategoryModel
    let category: String
    @ObservedObject var model: QuestionModel
    var badgeModel: BadgeModel?
    @State private var presentedQuestion: ExpandedQuestionState?

    private var questions: [Question] {
        model.questions(for: category)
    }

    private var expansionSourceID: String {
        "category.\(category)"
    }

    private var categoryColor: Color {
        categoryModel.color(for: category)
    }

    var body: some View {
        contentView
        .background(Color.theme.background)
        .navigationTitle(categoryModel.title(for: category))
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(item: $presentedQuestion) { expandedState in
            QuestionDetailModalShell(
                expandedState: expandedState,
                model: model,
                badgeModel: badgeModel,
                onClose: {
                    presentedQuestion = nil
                }
            )
        }
        .alert(
            String(localized: "common.error.title"),
            isPresented: Binding(
                get: { model.error != nil },
                set: { if !$0 { model.error = nil } }
            ),
            actions: {
                Button(String(localized: "common.ok")) { model.error = nil }
            },
            message: {
                if let error = model.error { Text(error) }
            }
        )
    }
    
    @ViewBuilder
    private var contentView: some View {
        if questions.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "main.category.emptyTitle"), systemImage: "text.badge.xmark")
            } description: {
                Text(
                    String(
                        format: String(localized: "main.category.emptyBody"),
                        locale: AppLocalization.currentLocale,
                        categoryModel.title(for: category)
                    )
                )
            } actions: {
                Button(String(localized: "common.refresh"), action: refreshQuestions)
                .accessibilityLabel(Text(String(localized: "main.category.refreshAccessibilityLabel")))
                .accessibilityHint(Text(String(localized: "main.category.refreshAccessibilityHint")))
            }
            .padding()
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(questions) { question in
                        QuestionCard(
                            question: question,
                            model: model,
                            headerStyle: .plain,
                            sourceID: expansionSourceID,
                            onTap: { expandQuestion(question) },
                            showImages: true,
                            showsShareButton: true,
                            badgeModel: badgeModel,
                            presentationStyle: .pagedFeed,
                            categoryColor: categoryColor
                        )
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(Color.theme.background)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 0)
            }
        }
    }

    private func refreshQuestions() {
        Task {
            await model.refreshQuestions()
        }
    }

    private func expandQuestion(_ question: Question) {
        presentedQuestion = ExpandedQuestionState(
            question: question,
            headerStyle: .plain
        )
    }
}

struct CategoryQuestionsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CategoryQuestionsView(
                category: "Daily",
                model: QuestionModel(localQuestions: Question.sampleQuestions),
                badgeModel: BadgeModel()
            )
        }
        .environmentObject(AuthModel())
        .environmentObject(FavoriteStore.previews)
        .environmentObject(GuestFavoriteModel())
        .environmentObject(CategoryModel(localCategories: Category.defaultCategories))
    }
}
