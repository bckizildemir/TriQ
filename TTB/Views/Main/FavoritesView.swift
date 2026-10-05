import SwiftUI
import FirebaseFirestore

// NavigationStack içermeyen içerik view'i — ProfileView'den push ile kullanılır
struct FavoritesContentView: View {
    @EnvironmentObject private var authModel: AuthModel
    @EnvironmentObject private var favoriteStore: FavoriteStore
    @EnvironmentObject private var guestFavoriteModel: GuestFavoriteModel
    @EnvironmentObject private var questionModel: QuestionModel

    @State private var presentedQuestion: ExpandedQuestionState?
    // Presented locally rather than through the model's global flag: this screen is
    // pushed inside ProfileView, which is itself reachable as a fullScreenCover from
    // Home, so a root-owned sheet would be asked to present from underneath a cover.
    @State private var isShowingGuestUpgrade = false

    private let expansionSourceID = "favorites"

    var body: some View {
        // Derived once per render and threaded down: reading `displayedFavoriteQuestions` for the
        // empty check and again for the `ForEach` ran the whole derivation twice.
        let favoriteQuestions = displayedFavoriteQuestions

        return Group {
            if shouldShowLoading {
                loadingView
            } else if favoriteQuestions.isEmpty {
                emptyStateView
            } else {
                questionListView(favoriteQuestions)
            }
        }
        .background(Color.theme.background)
        .alert(
            String(localized: "common.error.title"),
            isPresented: Binding(
                get: { favoriteStore.error != nil },
                set: { if !$0 { favoriteStore.error = nil } }
            ),
            actions: {
                Button(String(localized: "common.ok")) { favoriteStore.error = nil }
            },
            message: {
                if let error = favoriteStore.error { Text(error) }
            }
        )
        .navigationTitle(String(localized: "main.favorites.title"))
        .toolbarTitleDisplayMode(.inline)
        .fullScreenCover(item: $presentedQuestion) { expandedState in
            QuestionDetailModalShell(
                expandedState: expandedState,
                model: questionModel
            )
        }
        .sheet(isPresented: $isShowingGuestUpgrade) {
            GuestUpgradeView()
                .environmentObject(authModel)
        }
    }

    private var shouldShowLoading: Bool {
        favoriteStore.isLoading
    }

    private var shouldShowGuestStrip: Bool {
        authModel.isAnonymous && guestFavoriteModel.getFavoriteCount() > 0
    }

    private var displayedFavoriteQuestions: [Question] {
        favoriteStore.favorites
    }

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 100)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.slash")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text(String(localized: "main.favorites.emptyTitle"))
                .font(.headline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    private func questionListView(_ questions: [Question]) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if shouldShowGuestStrip {
                    GuestFavoriteStatusStrip(
                        count: guestFavoriteModel.getFavoriteCount(),
                        limit: GuestFavoriteModel.maxGuestFavorites,
                        onUpgrade: { isShowingGuestUpgrade = true }
                    )
                    .padding(.horizontal)
                }

                ForEach(questions) { question in
                    FavoriteQuestionCard(
                        question: question,
                        questionModel: questionModel,
                        sourceID: expansionSourceID,
                        onTap: {
                            presentedQuestion = ExpandedQuestionState(
                                question: question,
                                headerStyle: .plain
                            )
                        }
                    )
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

struct FavoriteQuestionCard: View {
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
            showImages: true,
            showsShareButton: true,
            presentationStyle: .pagedFeed,
            categoryColor: categoryModel.color(for: question.category)
        )
        .padding(.horizontal)
    }
}

// Standalone wrapper — bağımsız kullanım ve Preview için
struct FavoritesView: View {
    var body: some View {
        NavigationStack {
            FavoritesContentView()
        }
    }
}

#Preview {
    FavoritesView()
        .environmentObject(AuthModel())
        .environmentObject(FavoriteStore.previews)
        .environmentObject(GuestFavoriteModel())
        .environmentObject(QuestionModel())
        .environmentObject(CategoryModel(localCategories: Category.defaultCategories))
}
