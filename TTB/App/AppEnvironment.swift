import Foundation

/// The three service slots AD-3 moved onto `AppEnvironment`, as one value.
///
/// The three travel together by construction: `live()` supplies all three, `uiTest()` supplies
/// none, and no caller has ever needed to mix. Bundling them keeps `AppEnvironment.init` from
/// growing a fourth loose optional the next time a service slot moves here.
struct AppEnvironmentServices {
    /// The AI backend, or `nil` for the app's no-AI mode.
    ///
    /// `nil` is a designed fallback, not merely "do not construct": the editor shows no suggestion,
    /// which is not what a fake that throws would show. Removing the optionality needs real fakes
    /// and belongs to AD-5.
    let aiService: (any AIServiceProtocol)?

    /// The image-suggestion backend, or `nil` for the app's no-suggestion mode.
    let answerImageSuggestionService: AnswerImageSuggestionService?

    /// Where a saved answer is written, or `nil` for the app's local mode.
    ///
    /// `docs/adr/0005` calls this optionality the anti-pattern and names AD-3 *or AD-5* as its
    /// owner. AD-3 moves the decision; killing it needs a fake that saves for real, which is AD-5's.
    let answerPersister: AnswerPersisting?

    /// No AI backend, no image suggestions, and a local-only answer draft store — a harness's shape.
    ///
    /// Computed rather than a stored `static let`: the slots are non-`Sendable` existentials, so a
    /// stored instance would be global shared state, and an all-`nil` value costs nothing to build.
    static var none: AppEnvironmentServices {
        AppEnvironmentServices(
            aiService: nil,
            answerImageSuggestionService: nil,
            answerPersister: nil
        )
    }
}

/// Everything a screen needs from the app around it, as one value.
///
/// This is the seam AD-3 asked for. Before it, `AppEnvironmentRootView` took eleven models and six
/// UI-test harnesses re-declared the same wiring rather than pass through it, so the tests ran
/// against a second app wiring that had drifted from production. One value means a harness supplies
/// a fixture in one line, and `.appRoot(_:)` installs the same behaviour for both.
///
/// It is an `ObservableObject` that publishes nothing. The type exists to be held by `@StateObject`,
/// whose `wrappedValue` is an autoclosure and therefore builds the live models once, lazily —
/// `@State` would rebuild them on every `init`, opening a Firestore listener each time. Observation
/// stays on the individual models, which is where every screen already reads it.
@MainActor
final class AppEnvironment: ObservableObject {
    let authModel: AuthModel
    let questionModel: QuestionModel
    let answerModel: AnswerModel
    let favoriteStore: FavoriteStore
    let guestFavoriteModel: GuestFavoriteModel
    let questionListStore: QuestionListStore
    let sharedQuestionListStore: SharedQuestionListStore
    let profileModel: ProfileModel
    let categoryModel: CategoryModel
    let notificationService: NotificationService
    let deepLinkRouter: AppDeepLinkRouter
    let toastCenter: ToastCenter

    /// The badge listener every screen used to build for itself. `HomeView`'s guard covered one of
    /// four construction sites; `ProfileView`, `AnswersContentView`, and `MostAnsweredView` built
    /// theirs with none, so a harness that reached any of the three opened a live Firestore
    /// listener. This is FIX-6.
    let badgeModel: BadgeModel

    /// The service construction decision AD-3 moved here from the views that used to make it.
    ///
    /// It is here rather than in a view initializer because deciding it is a wiring job, and a view
    /// that decides it has to ask whether it runs inside a UI test. Two call sites shared the old
    /// launch-argument check for the image-suggestion service: the editor built one, and
    /// `LiveAnswerImageStore` built a second for the same purpose. One slot now feeds both.
    let services: AppEnvironmentServices

    var aiService: (any AIServiceProtocol)? { services.aiService }
    var answerImageSuggestionService: AnswerImageSuggestionService? { services.answerImageSuggestionService }
    var answerPersister: AnswerPersisting? { services.answerPersister }

    /// The save choreography, wired to this environment's persister and image services.
    ///
    /// The store lives here because the environment is what knows which persister to give it. The
    /// environment key keeps a cache-only default, so a screen outside `appEnvironment(_:)` still
    /// edits an answer and simply does not persist it.
    ///
    /// Built on first use, because `LiveAnswerImageStore` reaches `ImageService.shared`: a harness
    /// that never saves an answer still constructs no Firebase client, which is what the old
    /// environment-key default guaranteed.
    private(set) lazy var answerDraftStore: AnswerDraftStore = AnswerDraftStore(
        persister: services.answerPersister,
        images: LiveAnswerImageStore(suggestionService: services.answerImageSuggestionService)
    )

    /// How long `SimulatorSafeSheetDismissButton` refuses its own tap after a sheet appears.
    ///
    /// Zero everywhere except one harness. The button used to ask `UITestLaunchOptions` for this,
    /// which is a production view that knows a harness by name; the harness states the delay now.
    let sheetDismissDelay: Duration

    /// A link the process was launched with. It belongs here rather than as a second view parameter
    /// because it is launch input like everything else above, and a harness that drives a deep link
    /// sets it the same way the app does.
    let initialDeepLinkURL: URL?

    init(
        authModel: AuthModel,
        questionModel: QuestionModel,
        answerModel: AnswerModel,
        guestFavoriteModel: GuestFavoriteModel,
        questionListStore: QuestionListStore,
        sharedQuestionListStore: SharedQuestionListStore,
        profileModel: ProfileModel,
        categoryModel: CategoryModel,
        notificationService: NotificationService,
        deepLinkRouter: AppDeepLinkRouter,
        toastCenter: ToastCenter = ToastCenter(),
        favoriteStore: FavoriteStore? = nil,
        services: AppEnvironmentServices = .none,
        badgeModel: BadgeModel? = nil,
        sheetDismissDelay: Duration = .zero,
        initialDeepLinkURL: URL? = nil
    ) {
        self.sheetDismissDelay = sheetDismissDelay
        self.services = services
        self.authModel = authModel
        self.questionModel = questionModel
        self.answerModel = answerModel
        self.guestFavoriteModel = guestFavoriteModel
        self.questionListStore = questionListStore
        self.sharedQuestionListStore = sharedQuestionListStore
        self.profileModel = profileModel
        self.categoryModel = categoryModel
        self.notificationService = notificationService
        self.deepLinkRouter = deepLinkRouter
        self.toastCenter = toastCenter
        self.badgeModel = badgeModel ?? BadgeModel(store: LiveBadgeStore())
        self.initialDeepLinkURL = initialDeepLinkURL
        self.favoriteStore = favoriteStore ?? FavoriteStore(
            service: FavoriteService(),
            guestFavorites: guestFavoriteModel,
            resolveQuestions: { questionModel.questions(withIDs: $0) }
        )
    }

    /// The app's own wiring. Every model is built here and nowhere else on the production path.
    static func live(initialDeepLinkURL: URL? = nil) -> AppEnvironment {
        AppEnvironment(
            authModel: AuthModel(),
            questionModel: QuestionModel(),
            answerModel: AnswerModel(),
            guestFavoriteModel: GuestFavoriteModel(),
            questionListStore: QuestionListStore(),
            sharedQuestionListStore: SharedQuestionListStore(),
            profileModel: ProfileModel(),
            categoryModel: CategoryModel(),
            notificationService: NotificationService.shared,
            deepLinkRouter: AppDeepLinkRouter(),
            services: AppEnvironmentServices(
                aiService: AIService(),
                answerImageSuggestionService: AnswerImageSuggestionService(),
                answerPersister: QuestionService()
            ),
            initialDeepLinkURL: initialDeepLinkURL
        )
    }

    /// Who the favorites belong to right now. The store branches on this so no screen has to, and
    /// it lives here so the app root and every harness derive it the same way.
    var favoriteIdentity: FavoriteIdentity {
        .resolved(
            isAuthenticated: authModel.isAuthenticated,
            isAnonymous: authModel.isAnonymous,
            userId: authModel.currentUserId
        )
    }

    var guestFavoritePreviewQuestions: [Question] {
        questionModel.questions(withIDs: guestFavoriteModel.guestFavorites)
    }
}
