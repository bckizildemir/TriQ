import Foundation

#if DEBUG
extension AppEnvironment {
    /// A harness's wiring: fixture data, in-memory adapters, and no Firestore listeners.
    ///
    /// Only `authModel` and `questionModel` are required, because those are the two every harness
    /// genuinely differs on. Everything else has a fixture default, so a harness states what its
    /// test is about and nothing else — that is the ~700 lines of re-declared wiring AD-3 removed.
    ///
    /// This is a *used* adapter under `#if DEBUG`, not the unused one `docs/adr/0005` and `0007`
    /// warn about. It follows the precedent AD-1 set with `UITestFavoriteService`.
    static func uiTest(
        storage: UserDefaults,
        authModel: AuthModel,
        questionModel: QuestionModel,
        profileModel: ProfileModel? = nil,
        categoryModel: CategoryModel? = nil,
        questionListStore: QuestionListStore? = nil,
        sharedQuestionListStore: SharedQuestionListStore? = nil,
        sheetDismissDelay: Duration = .zero,
        initialDeepLinkURL: URL? = nil
    ) -> AppEnvironment {
        // Every harness used to clear this key itself, and the one that needs a seeded count could
        // not express it. One place decides both.
        UITestGuestFavoriteSeed.apply(to: storage)
        let guestFavorites = GuestFavoriteModel(storage: storage)

        return AppEnvironment(
            authModel: authModel,
            questionModel: questionModel,
            answerModel: AnswerModel(),
            guestFavoriteModel: guestFavorites,
            questionListStore: questionListStore ?? QuestionListStore(localLists: []),
            sharedQuestionListStore: sharedQuestionListStore
                ?? SharedQuestionListStore(localOwnedShares: []),
            profileModel: profileModel
                ?? ProfileModel(
                    userId: "ui-test-user",
                    startsAuthListener: false,
                    loadsRemoteData: false
                ),
            categoryModel: categoryModel ?? CategoryModel(localCategories: Category.defaultCategories),
            notificationService: .shared,
            deepLinkRouter: AppDeepLinkRouter(),
            // Guest ids resolve through the harness's own question model rather than a corpus
            // passed in beside it. The old `FavoriteStore.uiTest(corpus:)` took a second list that
            // could disagree with the one on screen; this cannot.
            favoriteStore: FavoriteStore(
                service: UITestFavoriteService(),
                guestFavorites: guestFavorites,
                resolveQuestions: { questionModel.questions(withIDs: $0) }
            ),
            badgeModel: BadgeModel(store: NoOpBadgeStore()),
            sheetDismissDelay: sheetDismissDelay,
            initialDeepLinkURL: initialDeepLinkURL
        )
    }
}
#endif
