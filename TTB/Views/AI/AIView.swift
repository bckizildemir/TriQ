import SwiftUI

struct AIView: View {
    @EnvironmentObject private var questionModel: QuestionModel
    @EnvironmentObject private var authModel: AuthModel
    @StateObject private var trioModel: TrioPromptModel
    @State private var showingGuestUpgrade = false
    @State private var showingCreateQuestion = false
    @State private var presentedQuestion: ExpandedQuestionState?

    private let expansionSourceID = "trio.feed"

    init(trioModel: TrioPromptModel? = nil) {
        _trioModel = StateObject(wrappedValue: trioModel ?? TrioPromptModel())
    }

    private var isAnonymousUser: Bool {
        authModel.isAnonymous
    }

    private var canCreateQuestion: Bool {
        authModel.isAuthenticated && !authModel.isAnonymous
    }

    var body: some View {
        let title = String(localized: "ai.trio.title")

        NavigationStack {
            ScrollView {
                feedSection
                    .padding(.top, 12)
                    .padding(.bottom, 28)
            }
            .background(Color.theme.background)
            .scrollDismissesKeyboard(.interactively)
            .navigationChromeTitle(
                semanticTitle: title,
                visualTitle: Text(title)
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentCreateQuestion()
                    } label: {
                        Label(String(localized: "ai.trio.createQuestion"), systemImage: "plus")
                    }
                    .accessibilityIdentifier("trio-create-question-button")
                    .accessibilityLabel(String(localized: "ai.trio.createQuestion"))
                }
            }
        }
        .sheet(isPresented: $showingGuestUpgrade) {
            GuestUpgradeView()
                .environmentObject(authModel)
                .accessibilityIdentifier("guest-upgrade-sheet")
        }
        .sheet(isPresented: $showingCreateQuestion) {
            TrioPromptComposerView(
                model: trioModel,
                onSubmit: publishPrompt
            )
            .environmentObject(questionModel)
            .environmentObject(authModel)
            .accessibilityIdentifier("trio-create-question-sheet")
        }
        .fullScreenCover(item: $presentedQuestion) { expandedState in
            QuestionDetailModalShell(
                expandedState: expandedState,
                model: questionModel,
                badgeModel: nil,
                onClose: {
                    presentedQuestion = nil
                }
            )
        }
    }

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "ai.trio.feedTitle"))
                    .font(.title3.bold())

                Text(String(localized: "ai.trio.feedBody"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            if questionModel.trioQuestions.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "ai.trio.emptyTitle"), systemImage: "square.and.pencil")
                } description: {
                    Text(String(localized: "ai.trio.emptyBody"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(questionModel.trioQuestions) { question in
                        QuestionCard(
                            question: question,
                            model: questionModel,
                            sourceID: expansionSourceID,
                            onTap: { expandQuestion(question) },
                            showImages: true,
                            showsShareButton: true,
                            presentationStyle: .pagedFeed,
                            categoryColor: .accentColor
                        )
                        .padding(.horizontal)
                    }
                }
            }
        }
    }

    private func expandQuestion(_ question: Question) {
        presentedQuestion = ExpandedQuestionState(
            question: question,
            headerStyle: .plain
        )
    }

    private func presentCreateQuestion() {
        guard canCreateQuestion else {
            showingGuestUpgrade = true
            return
        }

        showingCreateQuestion = true
    }

    private func publishPrompt() async -> Bool {
        if let _ = await trioModel.publish(using: questionModel) {
            trioModel.clearSuggestions()
            trioModel.ideaText = ""
            return true
        }

        return false
    }
}

#Preview {
    AIView()
        .environmentObject(QuestionModel())
        .environmentObject(AuthModel())
        .environmentObject(FavoriteStore.previews)
        .environmentObject(GuestFavoriteModel())
        .environmentObject(CategoryModel(localCategories: Category.defaultCategories))
}
