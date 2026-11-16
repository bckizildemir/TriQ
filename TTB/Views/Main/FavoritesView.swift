import SwiftUI
import FirebaseFirestore

// NavigationStack içermeyen içerik view'i — ProfileView'den push ile kullanılır
struct FavoritesContentView: View {
    @EnvironmentObject private var authModel: AuthModel
    @EnvironmentObject private var favoriteStore: FavoriteStore
    @EnvironmentObject private var guestFavoriteModel: GuestFavoriteModel
    @EnvironmentObject private var questionModel: QuestionModel

    @State private var presentedQuestion: ExpandedQuestionState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Removal settling: see `FavoritesScrollSettle`.
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    /// The list's own height, before `contentFloor` is applied.
    @State private var naturalContentHeight: CGFloat = 0
    /// The content never gets shorter than this. It holds the old height while a removal settles,
    /// so the scroll view does not pull its offset back in one frame.
    @State private var contentFloor: CGFloat = 0
    /// The ids the floor was last settled for; a natural-height change with the same ids is a
    /// layout change (lazy row estimates, Dynamic Type), not a removal.
    @State private var settledQuestionIDs: [String] = []
    /// Read when a removal settles, never in `body`, so scrolling does not re-render the view.
    @State private var latestScrollGeometry = LatestScrollGeometry()

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
                        onUpgrade: { guestFavoriteModel.requestGuestUpgrade() }
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
                    // A removed card fades (and, with full motion, shrinks a little) while the
                    // cards below slide up into the gap.
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            // Keyed on the ids, so any add, remove or reorder animates, whatever caused it.
            .animation(Self.listChangeAnimation, value: questions.map(\.id))
            .padding(.vertical)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                naturalContentHeight = height
            }
            .frame(minHeight: contentFloor, alignment: .top)
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: ScrollGeometry.self) { geometry in
            geometry
        } action: { _, geometry in
            latestScrollGeometry.value = geometry
        }
        .task(id: naturalContentHeight) {
            await settleContentFloor(for: questions.map(\.id))
        }
        .onDisappear {
            // The next list starts fresh: no held height, no stale geometry.
            contentFloor = 0
            settledQuestionIDs = []
            latestScrollGeometry.value = nil
        }
        .background(Color.theme.background)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 0)
        }
    }

    private static let listChangeAnimation = Animation.spring(duration: 0.35, bounce: 0)

    /// Lets the content shrink to its new height after a removal without a one-frame jump.
    ///
    /// While `contentFloor` holds the old height, the cards slide up and the scroll view keeps its
    /// offset. If the shorter list no longer reaches the bottom of the screen, this scrolls to the
    /// new bottom (or the top) with the same spring as the slide, waits for it, then drops the
    /// floor; the offset is already in range, so nothing jumps. Under Reduce Motion, and for a
    /// layout change with the same ids, the floor drops at once and the system clamps as before.
    private func settleContentFloor(for questionIDs: [String]) async {
        let newHeight = naturalContentHeight
        // Recorded only once a settle finishes, so a height change that cancels a running settle
        // is still treated as part of the same list change.
        let listChanged = questionIDs != settledQuestionIDs

        guard
            !reduceMotion,
            listChanged,
            newHeight < contentFloor,
            let geometry = latestScrollGeometry.value
        else {
            contentFloor = newHeight
            settledQuestionIDs = questionIDs
            return
        }

        if let target = FavoritesScrollSettle.target(
            contentOffsetY: geometry.contentOffset.y,
            topInset: geometry.contentInsets.top,
            bottomInset: geometry.contentInsets.bottom,
            containerHeight: geometry.containerSize.height,
            newContentHeight: newHeight
        ) {
            withAnimation(Self.listChangeAnimation) {
                scrollPosition.scrollTo(y: target)
            }
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                // A newer height took over; it settles from the floor still in place.
                return
            }
        }
        contentFloor = newHeight
        settledQuestionIDs = questionIDs
    }
}

/// A plain box for the latest scroll geometry. Not observed, so writing it on every scroll frame
/// does not re-render `FavoritesContentView`.
@MainActor
private final class LatestScrollGeometry {
    var value: ScrollGeometry?
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
